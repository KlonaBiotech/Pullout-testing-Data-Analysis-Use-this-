function forceLightFigure(fig)
%FORCELIGHTFIGURE Force a figure to render with a white background and
%   dark/black text and axes, regardless of the user's MATLAB desktop
%   theme (Preferences > Appearance > dark theme flips default figure
%   colors to a dark background with light text, which makes black data
%   points/markers invisible).
%
%   FORCELIGHTFIGURE(fig)
%
%   Call this immediately after creating a figure, before drawing
%   anything on it. Uses theme(fig,'light') where available (MATLAB
%   R2025a+, the "correct"/cascading way to do this - it also fixes
%   default colors for objects created afterward, like legends and
%   titles); falls back to no-op there and relies on the explicit
%   per-object color forcing already done in drawCurvesPlot.m,
%   drawMeanCurvesPlot.m, and drawSummaryBarChart.m for older releases.

    fig.Color = 'white';
    try
        theme(fig, 'light');
    catch
        % theme() doesn't exist before R2025a - the draw*Plot.m functions
        % explicitly set axes/text/legend colors themselves, so this is
        % a no-op fallback rather than a hard requirement.
    end
end
