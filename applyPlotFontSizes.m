function applyPlotFontSizes(ax, lgd)
%APPLYPLOTFONTSIZES Set larger, consistent font sizes on a chart - tick
%   labels, axis labels, title, and (if present) legend - so exported
%   graphs are readable when dropped into a slide/presentation without
%   needing to be resized/zoomed first.
%
%   APPLYPLOTFONTSIZES(ax, lgd)
%
%   lgd - optional legend handle; omit or pass [] if the chart has none
%   (e.g. drawSummaryBarChart.m, which labels groups via the x-axis
%   instead of a legend).

    if nargin < 2
        lgd = [];
    end

    ax.FontSize = 14;
    ax.Title.FontSize = 18;
    ax.XLabel.FontSize = 15;
    ax.YLabel.FontSize = 15;

    if ~isempty(lgd)
        lgd.FontSize = 12;
    end
end
