
**Development Log**

A drag-and-drop rocket builder written in Lua. Players assemble rockets from a parts catalog, snap pieces together, and arrange a visual staging order before launch.

---

## Table of Contents

- [Table of Contents](#table-of-contents)
- [Highlights](#highlights)
- [Developer Notes](#developer-notes)
  - [Scope Reduction](#scope-reduction)
  - [New Core Parts](#new-core-parts)
  - [Snapping \& Flipping](#snapping--flipping)
  - [Architecture \& File Management](#architecture--file-management)
  - [Staging System](#staging-system)
- [Code Walkthrough](#code-walkthrough)
  - [1. Parts Catalog](#1-parts-catalog)
  - [2. Snap Positioning Logic](#2-snap-positioning-logic)
  - [3. Visual Staging Trigger](#3-visual-staging-trigger)

---

## Highlights

| Feature | Summary |
|---|---|
| **Snapping** | Parts snap to the top or bottom of existing parts, with automatic flipping to the correct side |
| **Radial attachment** | Radial decouplers snap to the left or right of host parts such as fuel tanks |
| **Visual staging** | Drag-and-drop staging UI backed by unique part IDs |
| **OOP structure** | Object-oriented design keeps the file count manageable for the final game |

---

## Developer Notes

### Scope Reduction

Several complex parts were removed from the hangar. About half of them proved too difficult to program in the time available, so the focus shifted to a smaller set of parts that work well.

### New Core Parts

The following essential parts were added:

- Lander leg
- Small fuel tank
- Small engine
- Decoupler

### Snapping & Flipping

Snapping mechanics are implemented along with **automatic flipping** to the necessary sides, so parts attach correctly without manual adjustment.

### Architecture & File Management

Combining everything into a single hangar file could have improved efficiency, but it would have led to an unmanageable number of files in the final version of the game. Instead, the project follows **object-oriented programming (OOP)** principles to keep things modular.

### Staging System

A drag-and-drop **visual staging system** was designed using unique part IDs. This ensures rockets stage properly, a feature many simpler games skip.

---

## Code Walkthrough

### 1. Parts Catalog

The catalog groups every part by type. Each entry defines a unique `id`, a display `name`, its pixel dimensions, and a `category` used by the snapping logic.

```lua
local CATALOG = {
    Pods = {
        { id = "cockpit",   name = "Command Pod",   width = 24, height = 32, category = "cockpit" }
    },
    Fuel = {
        { id = "fuel",      name = "Fuel Tank",     width = 24, height = 40, category = "fuel" },
        { id = "miniFuel",  name = "Mini Fuel Tank",width = 16, height = 24, category = "miniFuel" }
    },
    Engines = {
        { id = "engine",    name = "Engine Bell",   width = 24, height = 28, category = "engine" },
        { id = "miniEngine",name = "Mini Rocket",   width = 16, height = 16, category = "miniEngine" }
    },
    Utility = {
        { id = "decoupler", name = "Decoupler Ring",width = 24, height = 12, category = "decoupler" },
        { id = "radialDec", name = "Radial Decoupler", width = 10, height = 16, category = "radialDec" },
        { id = "cone",      name = "Aero Cone",     width = 24, height = 16, category = "cone" },
        { id = "heatShield",name = "Heat Shield",   width = 24, height = 8,  category = "heatShield" },
        { id = "parachute", name = "Parachute Cap", width = 16, height = 12, category = "parachute" }
    }
}
```

**Parts at a glance**

| Group | Parts |
|---|---|
| Pods | Command Pod |
| Fuel | Fuel Tank, Mini Fuel Tank |
| Engines | Engine Bell, Mini Rocket |
| Utility | Decoupler Ring, Radial Decoupler, Aero Cone, Heat Shield, Parachute Cap |

---

### 2. Snap Positioning Logic

`getBestSnapPosition(part)` finds the closest valid attachment point for a dragged part.

**How it works**

1. Loop over every placed part, skipping the ones currently being dragged (the sub-assembly).
2. **Radial decouplers** snap to the left or right side of a host part, but only if vertically aligned within 15 px. The side is chosen by comparing the part's center to the host's center.
3. **All other parts** snap to the top or bottom of an existing part, horizontally centered on it.
4. A candidate only wins if it is closer than the current best distance (starting at `SNAP_THRESHOLD`) and passes `checkCollision`.
5. Returns the snap position, the parent host part, and which side it attached to (`"left"`, `"right"`, or `"center"`).

```lua
function getBestSnapPosition(part)
    local bestDist = SNAP_THRESHOLD
    local snapPos = nil
    local parentHost = nil
    local attachedSide = "center"

    for _, existing in ipairs(placedParts) do
        local isSelf = false
        for _, sub in ipairs(draggedSubAssembly) do
            if existing == sub then isSelf = true end
        end

        if not isSelf then
            if part.template.category == "radialDec" and isHostPart(existing.template.category) then
                local alignY = existing.y + (existing.template.height / 2) - (part.template.height / 2)
                
                if math.abs(part.y - alignY) < 15 then
                    local tankCenterX = existing.x + (existing.template.width / 2)
                    local partCenterX = part.x + (part.template.width / 2)

                    if partCenterX < tankCenterX then
                        local snapX = existing.x - part.template.width
                        local dist = math.abs(part.x - snapX)
                        if dist < bestDist and not checkCollision(snapX, alignY, part.template.width, part.template.height, draggedSubAssembly) then
                            bestDist = dist
                            snapPos = { x = snapX, y = alignY }
                            parentHost = existing
                            attachedSide = "left"
                        end
                    else
                        local snapX = existing.x + existing.template.width
                        local dist = math.abs(part.x - snapX)
                        if dist < bestDist and not checkCollision(snapX, alignY, part.template.width, part.template.height, draggedSubAssembly) then
                            bestDist = dist
                            snapPos = { x = snapX, y = alignY }
                            parentHost = existing
                            attachedSide = "right"
                        end
                    end
                end
            else
                local alignX = existing.x + (existing.template.width / 2) - (part.template.width / 2)
                
                local snapY_top = existing.y - part.template.height
                local distTop = math.abs(part.x - alignX) + math.abs(part.y - snapY_top)
                if distTop < bestDist and not checkCollision(alignX, snapY_top, part.template.width, part.template.height, draggedSubAssembly) then
                    bestDist = distTop
                    snapPos = { x = alignX, y = snapY_top }
                    parentHost = existing
                    attachedSide = "center"
                end

                local snapY_bottom = existing.y + existing.template.height
                local distBottom = math.abs(part.x - alignX) + math.abs(part.y - snapY_bottom)
                if distBottom < bestDist and not checkCollision(alignX, snapY_bottom, part.template.width, part.template.height, draggedSubAssembly) then
                    bestDist = distBottom
                    snapPos = { x = alignX, y = snapY_bottom }
                    parentHost = existing
                    attachedSide = "center"
                end
            end
        end
    end
    return snapPos, parentHost, attachedSide
end
```

---

### 3. Visual Staging Trigger

`triggerNextStage()` fires the next stage by working from the last stage backward. It finds the last stage that still has parts and removes those parts from `placedParts`. It then clears the selection if the selected part no longer exists, and rebuilds the staging UI.

```lua
function triggerNextStage()
    for i = #stages, 1, -1 do
        if #stages[i].parts > 0 then
            for _, stagePart in ipairs(stages[i].parts) do
                for idx, p in ipairs(placedParts) do
                    if p == stagePart then
                        table.remove(placedParts, idx)
                        break
                    end
                end
            end
            if selectedPartId and not hasIdInPlaced(selectedPartId) then
                selectedPartId = nil
            end
            rebuildStaging()
            break
        end
    end
end
```