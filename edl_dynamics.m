function dy = edl_dynamics(~, y, P, veh)
%EDL_DYNAMICS  3-DOF planar point-mass equations of motion over a spherical Earth.
%   State y = [h; v; gamma; x]
%     h     altitude MSL [m]
%     v     speed relative to atmosphere (non-rotating Earth) [m/s]
%     gamma flight path angle [rad], negative = descending
%     x     downrange distance along surface [m]
%   veh fields: mass [kg], CdA [m^2], LD [-], bank [deg]
h = y(1); v = y(2); gam = y(3);
r = P.Re + h;
[rho, ~, ~, g] = atmosphere(h);
qdyn = 0.5*rho*v^2;
Dr = qdyn*veh.CdA/veh.mass;               % drag accel [m/s^2]
Lf = veh.LD*Dr*cosd(veh.bank);            % lift accel in the vertical plane [m/s^2]
dy = [ v*sin(gam);
      -Dr - g*sin(gam);
       Lf/v + (v/r - g/v)*cos(gam);
       v*cos(gam)*P.Re/r ];
end
