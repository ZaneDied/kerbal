# Bimba Flamingo

component

cockpit, fuel, engine, wheel, lander, coupling

# Game Architecture Breakdown & Physics Systems

## Recommended File Structure
* **`physics.lua` (Orbital & General Physics):** Handles planetary gravity, velocity vectors, drag calculations, and general movement through space.
* **`atmosphere.lua` (Planet Science):** Manages atmospheric density layers, scale height formulas, and temperature/pressure curves based on altitude.
* **`structural.lua` (Structural Physics):** Handles component stress, structural limits, and whether parts can withstand the thermal and physical loads of reentry.
* **`particles.lua` (Particle Science):** Manages the air molecule array, spawning behavior, and fluid-sliding/collision math.
* **`vfx.lua` & `ui.lua` (Visuals & UI):** Keep these completely separate. `vfx.lua` handles the plasma glow, colors, and camera shake, while `ui.lua` draws your prograde vectors, telemetry HUD, and text.

---

## Detailed Physics & Equations (Kerbal-Style System)

### 1. Atmosphere Science (`atmosphere.lua`)
KSP uses an exponential scale-height model to calculate atmospheric density ($\rho$) as a function of altitude ($h$). 

$$ \rho(h) = \rho_0 e^{-\frac{h}{H}} $$

* **$\rho_0$**: Air density at sea level (e.g., $1.225 \text{ kg/m}^3$ for Earth-like planets).
* **$h$**: Current altitude in meters.
* **$H$**: Atmospheric scale height (e.g., $7,500 \text{ m}$), which dictates how quickly the atmosphere thins out as you go higher.

### 2. Orbital & General Physics (`physics.lua`)
This module tracks movement, gravity, and aerodynamic deceleration (drag). The core of atmospheric flight relies on **Dynamic Pressure** ($q$), which dictates both aerodynamic forces and structural stress:

$$ q = \frac{1}{2} \rho v^2 $$

From dynamic pressure, the deceleration caused by drag ($a_{\text{drag}}$) is calculated as:

$$ a_{\text{drag}} = \frac{q \cdot C_d \cdot A}{m} $$

* **$v$**: Velocity magnitude ($\text{m/s}$).
* **$C_d$**: Drag coefficient (blunt capsule has a higher $C_d$ around $1.0$ to $1.4$, while a sharp cone is much lower, around $0.3$ to $0.5$).
* **$A$**: Reference cross-sectional area.
* **$m$**: Mass of the module.

### 3. Structural Physics (`structural.lua`)
In KSP-style mechanics, structural integrity and part heating are driven directly by dynamic pressure and shockwave friction. The skin temperature or heat flux ($Q_{\text{flux}}$) experienced by a structural part scales proportionally with velocity cubed or squared in dense air:

$$ Q_{\text{flux}} = k \cdot \sqrt{\rho} \cdot v^3 $$

* If $Q_{\text{flux}}$ or the G-force load exceeds a part's maximum tolerance, the structural physics module triggers failure states (e.g., breaking off pieces or overheating).

### 4. Particle Science (`particles.lua`)
Instead of global math, individual air particles interact with structural layout using vector math. When a particle collides with a craft's bounding geometry, its velocity vector ($\vec{v}$) is split into normal ($\vec{n}$) and tangential ($\vec{t}$) components:

$$ v_n = \vec{v} \cdot \hat{n}, \quad v_t = \vec{v} \cdot \hat{t} $$

The particle transfers momentum to create drag, and the kinetic energy lost during this impact is converted into thermal energy:

$$ \Delta T_{\text{particle}} \propto |v_n| $$