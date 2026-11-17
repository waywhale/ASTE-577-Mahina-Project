%% SWEEP_ENTRY_ANGLE  Trade study: how do peak g, peak heating and heat load vary with entry angle?
%  Supports the "define entry conditions" and "level 2 requirements" report sections.
%  Also try P.veh.LD = 0.3 and P.veh.bank_deg = 60 to explore the PDR's lifting/skip-entry idea.
clear; close all;
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));

gammas = -10:0.5:-5;                    % deg
res = nan(numel(gammas), 3);
for k = 1:numel(gammas)
    P = edl_params(); P.entry.gamma0_deg = gammas(k); P = size_chutes(P);
    S = run_edl_sim(P);
    res(k,:) = [S.peak_g, S.peak_q, S.heat_load/1e3];
end
figure; yyaxis left; plot(gammas, res(:,1), '-o'); ylabel('Peak decel (g)');
yyaxis right; plot(gammas, res(:,3), '-s'); ylabel('Heat load (kJ/cm^2)');
xlabel('Entry flight path angle (deg)'); grid on; title('Entry-angle trade (ballistic)');
saveas(gcf, fullfile(root,'results','entry_angle_trade.png'));
disp(array2table([gammas' res], 'VariableNames', {'gamma_deg','peak_g','peak_q_Wcm2','heat_load_kJcm2'}));
