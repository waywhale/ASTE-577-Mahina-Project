%% MAIN_EDL  Run the Team MAHINA Earth-entry simulation and produce deliverable numbers.
%  Usage (from VS Code: open this file, then click "Run" in the MATLAB extension,
%  or in the MATLAB command window:  >> main_edl )
%
%  Produces (calculation deliverables):
%    - velocity vs altitude (with EDL phases/events)
%    - downrange vs altitude
%    - heat rate vs altitude
%    - peak deceleration + altitude, peak heating + altitude, total heat load
%    - parachute sizing + opening loads
%  Writes results/edl_timeline.csv and ../flight_computer/mission_config.json
clear; close all; clc;
root = fileparts(mfilename('fullpath'));
addpath(genpath(root));

P = edl_params();
P = size_chutes(P);
S = run_edl_sim(P);

%% ---- Summary ---------------------------------------------------------
fprintf('\n===== MAHINA EDL SUMMARY (convective heating only!) =====\n');
fprintf('Entry:   h0 = %.0f km, v0 = %.2f km/s, gamma0 = %.1f deg\n', P.entry.h0/1e3, P.entry.v0/1e3, P.entry.gamma0_deg);
fprintf('Vehicle: m = %.0f kg, D = %.2f m, beta = %.0f kg/m^2\n', P.veh.mass, P.veh.diam, P.veh.mass/(P.veh.Cd*P.veh.area));
fprintf('Peak deceleration : %.1f g at %.1f km (t = %.0f s)\n', S.peak_g, S.h_peak_g/1e3, S.t_peak_g);
fprintf('Peak heat rate    : %.0f W/cm^2 at %.1f km (t = %.0f s)\n', S.peak_q, S.h_peak_q/1e3, S.t_peak_q);
fprintf('Total heat load   : %.0f J/cm^2 (%.1f kJ/cm^2)\n', S.heat_load, S.heat_load/1e3);
fprintf('Landing speed     : %.1f m/s, downrange %.0f km, flight time %.0f s\n', S.v_land, S.downrange_km, S.t_land);
fprintf('Drogue: D = %.1f m, mass ~ %.1f kg | Main: D = %.1f m, mass ~ %.1f kg\n', ...
    P.chute.D_drogue, P.chute.mass_drogue, P.chute.D_main, P.chute.mass_main);

% parachute opening loads  F = Cx * q * CdA   (at deploy conditions)
iD = find(S.phase == 2, 1);  iM = find(S.phase == 3, 1);
if ~isempty(iD), fprintf('Drogue opening load ~ %.1f kN at Mach %.2f, q = %.0f Pa\n', P.chute.Cx*S.qdyn(iD)*P.chute.CdA_drogue/1e3, S.mach(iD), S.qdyn(iD)); end
if ~isempty(iM), fprintf('Main   opening load ~ %.1f kN at Mach %.2f, q = %.0f Pa\n', P.chute.Cx*S.qdyn(iM)*P.chute.CdA_main/1e3,  S.mach(iM), S.qdyn(iM)); end

fprintf('\nEvent timeline:\n');
for k = 1:numel(S.events)
    e = S.events(k);
    fprintf('  T+%6.1f s   h = %6.2f km   v = %7.1f m/s   %s\n', e.t, e.h/1e3, e.v, e.name);
end

%% ---- Plots -------------------------------------------------------------
plot_edl(S, fullfile(root,'results'));

%% ---- Save outputs ------------------------------------------------------
tbl = table(S.t, S.h, S.v, rad2deg_(S.gamma), S.x, S.mach, S.accel_g, S.qdot, S.phase, ...
    'VariableNames', {'t_s','h_m','v_mps','gamma_deg','downrange_m','mach','accel_g','qdot_Wcm2','phase'});
writetable(tbl, fullfile(root,'results','edl_timeline.csv'));
save(fullfile(root,'results','edl_results.mat'), 'S');

% Hand the triggers/constants to the Raspberry Pi flight computer
cfg = struct();
cfg.entry = P.entry; cfg.veh = P.veh; cfg.heat = P.heat; cfg.land = P.land;
cfg.chute = P.chute; cfg.Re = P.Re; cfg.mu = P.mu; cfg.g0 = P.g0;
cfg.expected = struct('peak_g',S.peak_g,'peak_q_Wcm2',S.peak_q,'heat_load_Jcm2',S.heat_load, ...
                      't_land_s',S.t_land,'v_land_mps',S.v_land);
fid = fopen(fullfile(root,'..','flight_computer','mission_config.json'),'w');
fwrite(fid, jsonencode(cfg, 'PrettyPrint', true)); fclose(fid);
fprintf('\nSaved results/edl_timeline.csv and flight_computer/mission_config.json\n');

function d = rad2deg_(r), d = r*180/pi; end
