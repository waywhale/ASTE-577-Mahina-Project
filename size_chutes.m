function P = size_chutes(P)
%SIZE_CHUTES  Size drogue and main parachute from the targets in edl_params.
%   Main chute: steady-state  m*g = 0.5*rho*v^2*Cd*A  at the landing altitude
%   (body drag ignored in sizing = conservative).
rho_land = atmosphere(P.land.h);
m_main   = P.veh.mass - P.veh.shield_m;      % shield is jettisoned at main deploy
P.chute.CdA_main = 2*m_main*P.g0/(rho_land*P.chute.v_land_target^2);
P.chute.A_main   = P.chute.CdA_main/P.chute.Cd_main;
P.chute.D_main   = sqrt(4*P.chute.A_main/pi);
P.chute.A_drogue = pi*P.chute.D_drogue^2/4;
P.chute.CdA_drogue = P.chute.Cd_drogue*P.chute.A_drogue;
P.chute.mass_main   = P.chute.mass_per_area*P.chute.A_main;
P.chute.mass_drogue = P.chute.mass_per_area*P.chute.A_drogue;
end
