# Crick laws

- **Water balance:** current water equals initial water plus actual admitted water minus actual exported water, subject to the validation bound `abs(residual) <= 1e-8 * max(1, expectedWater)`.
- **Material balance:** ground plus carried sediment plus exported sediment plus excavated material equals initial ground plus externally added fill, subject to the validation bound `abs(residual) <= 1e-8 * max(1, expectedMaterial)`.
- **Bounded state:** authoritative scalar state is finite. Water depth, carried sediment, accounting totals, and transfer amounts are nonnegative; ground height is floor-bounded and flow components may be signed. Transfers are bounded by available quantities and model limits.
- **Ground edits preserve water:** digging or filling changes ground only. A submerged bed rise retains local water depth; ordinary later ticks redistribute water.
- **Ordinary fill:** externally added fill joins the single ground material and is erodible, transportable, depositable, and exportable by the existing kernel.
- **No inventory:** digging records excavated material and filling records actual externally added ground; neither operation creates a player stockpile.
- **One world clock:** active play advances fixed simulation ticks. Menus, legacy presentation, and inactive app phases pause it; elapsed time away never becomes catch-up work.
- **Truthful causality:** product copy and evidence distinguish measured state, co-occurrence, and paired intervention effects.
- **Versioned authority:** a snapshot is accepted only when its envelope, compatibility identity, complete state, and conservation laws validate. Explicit older migrations may be pragmatic and lossy; they produce current authority rather than running prior engines.
