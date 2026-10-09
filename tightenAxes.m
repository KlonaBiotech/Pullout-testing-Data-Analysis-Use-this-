function tightenAxes(ax, paddingFraction)
%TIGHTENAXES Explicitly auto-fit axes limits to the plotted data with a
%   small, predictable margin, rather than leaving it to MATLAB's default
%   auto-limit padding (which can leave a surprising amount of empty
%   space, especially with a single outlier point stretching the range).
%
%   TIGHTENAXES(ax, paddingFraction)
%
%   paddingFraction - margin added on each side as a fraction of the
%   data range (default 0.05 = 5%).
%
%   Call this last, after all plotting/legend/title calls on ax.

    if nargin < 2
        paddingFraction = 0.05;
    end

    axis(ax, 'tight');
    xl = xlim(ax);
    yl = ylim(ax);
    xr = xl(2) - xl(1);
    yr = yl(2) - yl(1);
    if xr == 0
        xr = 1;
    end
    if yr == 0
        yr = 1;
    end
    xlim(ax, [xl(1) - paddingFraction * xr, xl(2) + paddingFraction * xr]);
    ylim(ax, [yl(1) - paddingFraction * yr, yl(2) + paddingFraction * yr]);
    % (xlim/ylim above already set XLimMode/YLimMode to 'manual' with
    % these exact padded values - that's intentional, so the limits stay
    % fixed rather than being silently recomputed by anything plotted
    % afterward.)
end
