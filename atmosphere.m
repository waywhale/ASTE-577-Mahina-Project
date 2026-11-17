function [rho, T, a, g] = atmosphere(h)
%ATMOSPHERE  Earth atmosphere from tabulated US Standard Atmosphere 1976.
%   [rho,T,a,g] = atmosphere(h)   h in m (scalar or vector)
%   rho [kg/m^3] (log-linear interpolation), T [K], a [m/s], g [m/s^2]
%   Altitudes are clamped to 0-150 km for density/temperature.
persistent hk lrho Tk
if isempty(hk)
    hk    = [0 10 20 30 40 50 60 70 80 90 100 110 120 130 150]*1e3;
    rho_k = [1.225 0.4135 0.0889 0.0184 3.996e-3 1.027e-3 3.097e-4 8.283e-5 ...
             1.846e-5 3.416e-6 5.604e-7 9.708e-8 2.222e-8 8.152e-9 2.076e-9];
    Tk    = [288.15 223.25 216.65 226.51 250.35 270.65 247.02 219.58 ...
             198.64 186.87 195.08 240 360 469.3 634];
    lrho  = log(rho_k);
end
hc  = min(max(h, 0), hk(end));
rho = exp(interp1(hk, lrho, hc, 'linear'));
T   = interp1(hk, Tk, hc, 'linear');
a   = sqrt(1.4*287.053*T);
g   = 3.986004418e14 ./ (6378137 + h).^2;
end
