function drawCurvesPlot(ax, curves, colorMap, xLimits, yLimits)
%DRAWCURVESPLOT Plot all individual force-displacement curves on ax.
%
%   DRAWCURVESPLOT(ax, curves, colorMap, xLimits, yLimits)
%
%   ax       - target axes (works with both a UIAxes and a regular figure axes)
%   curves   - struct array with fields Group, Treatment, Displacement, Load
%   colorMap - containers.Map from combo label (see curveComboLabel.m) to
%              RGB, built by assignCurveColors.m
%   xLimits  - optional [min max] to override auto-scaling on the
%              displacement axis (e.g. cut off a long tail so the rest of
%              the data isn't squashed). Omit or pass [] for auto.
%   yLimits  - optional [min max] to override auto-scaling on the load
%              axis. Omit or pass [] for auto.
%
%   Solid lines only, one distinct color per unique Group/Treatment combo
%   (no line-style encoding - color alone carries the grouping, so there
%   is never a dashed/dotted line to misread).

    if nargin < 4
        xLimits = [];
    end
    if nargin < 5
        yLimits = [];
    end

    cla(ax);
    hold(ax, 'on');

    comboLabels = strings(numel(curves), 1);
    for i = 1:numel(curves)
        comboLabels(i) = curveComboLabel(curves(i).Group, curves(i).Treatment);
    end
    uCombos = sortByConcentration(comboLabels);

    for k = 1:numel(uCombos)
        rgb = colorMap(char(uCombos(k)));
        idx = find(comboLabels == uCombos(k));
        for j = 1:numel(idx)
            i = idx(j);
            if j == 1
                plot(ax, curves(i).Displacement, curves(i).Load, ...
                    'Color', rgb, 'LineStyle', '-', 'LineWidth', 1.4, ...
                    'DisplayName', uCombos(k));
            else
                plot(ax, curves(i).Displacement, curves(i).Load, ...
                    'Color', rgb, 'LineStyle', '-', 'LineWidth', 1.4, ...
                    'HandleVisibility', 'off');
            end
        end
    end

    hold(ax, 'off');
    xlabel(ax, 'Displacement (mm)');
    ylabel(ax, 'Load (N)');
    title(ax, 'All Individual Pull-Out Curves');
    grid(ax, 'on');
    box(ax, 'on');
    lgd = legend(ax, 'show', 'Location', 'best');

    % Explicit light styling: don't rely on the figure/desktop theme,
    % which can flip this to a dark background with light text and make
    % dark-colored data points/markers invisible.
    ax.Color = 'white';
    ax.XColor = 'k';
    ax.YColor = 'k';
    ax.GridColor = [0.15 0.15 0.15];
    ax.GridAlpha = 0.3;
    ax.Title.Color = 'k';
    lgd.TextColor = 'k';
    lgd.Color = 'white';
    applyPlotFontSizes(ax, lgd);

    tightenAxes(ax);

    % Manual overrides win over auto-scaling, applied after so a blank
    % field on either axis still falls back to the auto-tightened value.
    if ~isempty(xLimits)
        xlim(ax, xLimits);
    end
    if ~isempty(yLimits)
        ylim(ax, yLimits);
    end
end
