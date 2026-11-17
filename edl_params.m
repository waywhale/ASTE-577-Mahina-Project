function P = edl_params()
%EDL_PARAMS  Single source of truth for every EDL assumption.
%   Change numbers HERE (not inside other files) and document why in
%   docs/assumptions.md. Values marked [PDR] come from the Team MAHINA PDR
%   deck; values marked [ASSUMED] are placeholders the team must replace
%   with a referenced value before the report is submitted.

% ---- Earth / environment -------------------------------------------------
P.Re = 6378137;            % m   equatorial radius
P.mu = 3.986004418e14;     % m^3/s^2
P.g0 = 9.80665;            % m/s^2

% ---- Entry conditions ----------------------------------------------------
P.entry.h0         = 122e3;   % m    entry interface altitude (Apollo/Stardust convention)
P.entry.v0         = 11000;   % m/s  [PDR] ~11 km/s lunar-return entry speed
P.entry.gamma0_deg = -7;      % deg  [PDR] 7 deg entry angle (negative = descending)

% ---- Entry vehicle (the Ascender with heat shield) -----------------------
P.veh.mass      = 430;        % kg  [PDR] Ascender on-orbit dry mass incl. 50 kg payload. Verify propellant left at entry.
P.veh.shield_m  = 18;         % kg  [PDR] PICA heat shield (4.5 cm incl. 50% margin)
P.veh.diam      = 1.4;        % m   [ASSUMED] back-computed from 18 kg PICA @ 4.5 cm; confirm vs CAD
P.veh.Cd        = 1.2;        % -   [ASSUMED] hypersonic blunt body; replace with aero database value
P.veh.Rn        = 0.7;        % m   [ASSUMED] effective nose radius for stagnation heating
P.veh.LD        = 0.0;        % -   0 = ballistic baseline. PDR mentions a lifting "skip entry": explore with LD and bank_deg
P.veh.bank_deg  = 0;          % deg bank angle (0 = full lift up). Only matters if LD > 0
P.veh.Cd_sub    = 0.8;        % -   [ASSUMED] body drag under parachute
P.veh.area      = pi*P.veh.diam^2/4;   % m^2

% ---- Heating -------------------------------------------------------------
P.heat.k_sg = 1.7415e-4;      % Sutton-Graves constant, Earth air (SI): q = k*sqrt(rho/Rn)*v^3  [W/m^2]
% NOTE: Sutton-Graves is convective only. At 11 km/s radiative heating is
% non-negligible - see src/radiative_heating.m (TODO for the team).

% ---- Parachutes (dual stage per PDR) ------------------------------------
P.chute.mach_drogue   = 1.5;   % -   drogue deploy trigger (Mach)          [ASSUMED]
P.chute.Cd_drogue     = 0.55;  % -   conical ribbon                         [ASSUMED]
P.chute.D_drogue      = 4.0;   % m   drogue nominal diameter (trade: drogue vs main opening load) [ASSUMED]
P.chute.Cd_main       = 0.80;  % -   ringsail                               [ASSUMED]
P.chute.h_main_agl    = 3000;  % m   main deploy altitude above ground      [ASSUMED]
P.chute.v_land_target = 10;    % m/s target steady descent rate at landing  [ASSUMED]
P.chute.mass_per_area = 0.35;  % kg/m^2 canopy+lines+bag+deployer           [ASSUMED]
P.chute.Cx            = 1.5;   % -   opening-shock factor                   [ASSUMED]

% ---- Landing site: Utah Test and Training Range dry lake bed [PDR ConOps] -
P.land.h = 1300;               % m MSL, approximate dry-lakebed elevation
end
