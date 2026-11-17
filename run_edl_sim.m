function S = run_edl_sim(P)
%RUN_EDL_SIM  Integrate the full EDL timeline: entry -> drogue -> main -> landing.
%   Phases: 1 = hypersonic/supersonic entry, 2 = drogue, 3 = main (shield jettisoned)
%   Triggers: drogue @ Mach <= P.chute.mach_drogue; main @ h <= landing + h_main_agl;
%             landing @ h <= P.land.h.
d2r = pi/180;
y0  = [P.entry.h0; P.entry.v0; P.entry.gamma0_deg*d2r; 0];
opts = odeset('RelTol',1e-8,'AbsTol',1e-6,'MaxStep',1);

veh{1} = struct('mass',P.veh.mass, 'CdA',P.veh.Cd*P.veh.area, ...
                'LD',P.veh.LD, 'bank',P.veh.bank_deg);
veh{2} = struct('mass',P.veh.mass, ...
                'CdA',P.veh.Cd_sub*P.veh.area + P.chute.CdA_drogue, 'LD',0, 'bank',0);
veh{3} = struct('mass',P.veh.mass - P.veh.shield_m, ...
                'CdA',P.veh.Cd_sub*P.veh.area + P.chute.CdA_main, 'LD',0, 'bank',0);

evfun{1} = @(t,y) ev_entry(t,y,P);
evfun{2} = @(t,y) ev_main(t,y,P);
evfun{3} = @(t,y) ev_land(t,y,P);

T = []; Y = []; PH = []; tstart = 0; y = y0; tev = nan(1,3);
for k = 1:3
    o = odeset(opts, 'Events', evfun{k});
    [t, yy, te, ~, ie] = ode45(@(t,y) edl_dynamics(t,y,P,veh{k}), [tstart tstart+4000], y, o);
    if k > 1, t = t(2:end); yy = yy(2:end,:); end
    T = [T; t]; Y = [Y; yy]; PH = [PH; k*ones(numel(t),1)]; %#ok<AGROW>
    if isempty(te)
        warning('Phase %d ended without hitting its trigger (check params).', k); break
    end
    tev(k) = te(end);
    if k == 1 && ie(end) == 2
        warning('Vehicle reached the ground before drogue deploy.'); break
    end
    tstart = t(end); y = yy(end,:)';
end

S.P = P; S.t = T; S.h = Y(:,1); S.v = Y(:,2); S.gamma = Y(:,3); S.x = Y(:,4); S.phase = PH;

% ---- diagnostics ---------------------------------------------------------
[rho, ~, a, ~] = atmosphere(S.h);
S.mach = S.v./a; S.rho = rho; S.qdyn = 0.5*rho.*S.v.^2;
CdA = zeros(size(T)); m = zeros(size(T)); LD = zeros(size(T)); bk = zeros(size(T));
for k = 1:3
    i = PH == k;
    CdA(i) = veh{k}.CdA; m(i) = veh{k}.mass; LD(i) = veh{k}.LD; bk(i) = veh{k}.bank;
end
Dr = S.qdyn.*CdA./m; Lf = LD.*Dr.*cosd(bk);
S.accel_g = sqrt(Dr.^2 + Lf.^2)/P.g0;                     % sensed aero acceleration [g]
qconv = P.heat.k_sg*sqrt(rho/P.veh.Rn).*S.v.^3;           % W/m^2
S.qdot = (qconv + radiative_heating(rho,S.v,P.veh.Rn))/1e4;  % W/cm^2
S.qdot(PH > 1) = 0;                                       % heating only counted in phase 1

[S.peak_g, i1] = max(S.accel_g);  S.h_peak_g = S.h(i1);  S.t_peak_g = S.t(i1);
[S.peak_q, i2] = max(S.qdot);     S.h_peak_q = S.h(i2);  S.t_peak_q = S.t(i2);
S.heat_load = trapz(S.t, S.qdot);                         % J/cm^2
S.v_land = S.v(end); S.t_land = S.t(end); S.downrange_km = S.x(end)/1e3;

% ---- event list (for plots, telemetry, flight computer triggers) --------
add = @(n,t) struct('name',n,'t',t,'h',interp1(S.t,S.h,t),'v',interp1(S.t,S.v,t));
ev = add('Atmospheric entry', 0);
ev(end+1) = add('Peak heating', S.t_peak_q);
ev(end+1) = add('Peak deceleration', S.t_peak_g);
if ~isnan(tev(1)), ev(end+1) = add('Drogue deploy', tev(1)); end
if ~isnan(tev(2))
    ev(end+1) = add('Main deploy + heat shield sep', tev(2));
    ev(end+1) = add('Start terminal descent', tev(2));
end
if ~isnan(tev(3)), ev(end+1) = add('Landing', tev(3)); end
[~,ord] = sort([ev.t]); S.events = ev(ord);
end

% ---- event functions -------------------------------------------------------
function [value,isterminal,direction] = ev_entry(~,y,P)
[~,~,a,~] = atmosphere(y(1));
value = [y(2)/a - P.chute.mach_drogue; y(1) - P.land.h];
isterminal = [1;1]; direction = [-1;-1];
end
function [value,isterminal,direction] = ev_main(~,y,P)
value = [y(1) - (P.land.h + P.chute.h_main_agl); y(1) - P.land.h];
isterminal = [1;1]; direction = [-1;-1];
end
function [value,isterminal,direction] = ev_land(~,y,P)
value = y(1) - P.land.h; isterminal = 1; direction = -1;
end
