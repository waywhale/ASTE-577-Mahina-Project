function plot_edl(S, outdir)
%PLOT_EDL  Required EDL plots. Saves PNGs into outdir.
if nargin < 2, outdir = pwd; end
if ~exist(outdir,'dir'), mkdir(outdir); end
cols = [0.85 0.33 0.10; 0.00 0.45 0.74; 0.47 0.67 0.19];   % phase colours
names = {'Entry (aeroshell)','Drogue','Main + terminal'};

% 1) Velocity vs altitude with phases + events
f1 = figure('Name','Velocity vs altitude'); hold on; grid on;
for k = 1:3
    i = S.phase == k; if any(i), plot(S.v(i)/1e3, S.h(i)/1e3, 'Color', cols(k,:), 'LineWidth', 2, 'DisplayName', names{k}); end
end
mk = {'o','s','^','v','d','p'};
for k = 1:numel(S.events)
    e = S.events(k);
    plot(e.v/1e3, e.h/1e3, mk{mod(k-1,6)+1}, 'MarkerFaceColor','k','MarkerEdgeColor','k','HandleVisibility','off');
    text(e.v/1e3, e.h/1e3, ['  ' e.name], 'FontSize', 8);
end
xlabel('Velocity (km/s)'); ylabel('Altitude (km)'); title('Velocity vs Altitude'); legend('Location','southwest');
saveas(f1, fullfile(outdir,'velocity_vs_altitude.png'));

% 2) Downrange vs altitude
f2 = figure('Name','Downrange vs altitude'); plot(S.x/1e3, S.h/1e3, 'LineWidth', 2); grid on;
xlabel('Downrange (km)'); ylabel('Altitude (km)'); title('Downrange vs Altitude');
saveas(f2, fullfile(outdir,'downrange_vs_altitude.png'));

% 3) Heat rate vs altitude
f3 = figure('Name','Heat rate vs altitude'); i = S.phase == 1;
plot(S.qdot(i), S.h(i)/1e3, 'LineWidth', 2); grid on; hold on;
plot(S.peak_q, S.h_peak_q/1e3, 'ro', 'MarkerFaceColor','r');
text(S.peak_q, S.h_peak_q/1e3, sprintf('  peak %.0f W/cm^2', S.peak_q));
xlabel('Stagnation-point heat rate (W/cm^2)'); ylabel('Altitude (km)');
title('Heat Rate vs Altitude (convective only)');
saveas(f3, fullfile(outdir,'heat_rate_vs_altitude.png'));

% 4) Deceleration vs altitude
f4 = figure('Name','Deceleration vs altitude'); plot(S.accel_g, S.h/1e3, 'LineWidth', 2); grid on; hold on;
plot(S.peak_g, S.h_peak_g/1e3, 'ro', 'MarkerFaceColor','r');
text(S.peak_g, S.h_peak_g/1e3, sprintf('  peak %.1f g', S.peak_g));
xlabel('Deceleration (g)'); ylabel('Altitude (km)'); title('Deceleration vs Altitude');
saveas(f4, fullfile(outdir,'decel_vs_altitude.png'));
end
