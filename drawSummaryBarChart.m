function uCombos = drawSummaryBarChart(ax, dataTable, valueCol, yLabelStr, colorMap, yLimits)
%DRAWSUMMARYBARCHART Mean bar + SD error bar + jittered individual points,
%   one bar per Group/Treatment combo - matches the "Summary Data" bar
%   chart style (mean bar, SD whisker, dots for each sample).
%
%   uCombos = DRAWSUMMARYBARCHART(ax, dataTable, valueCol, yLabelStr, colorMap, yLimits)
%
%   dataTable - table with a Group column, a valueCol column, and
%               optionally a Treatment column (used if present)
%   valueCol  - name of the numeric column to summarize, e.g. 'PeakForce_N'
%   yLabelStr - y-axis label, e.g. 'Peak Pull Out Force (N)'
%   colorMap  - containers.Map from combo label (curveComboLabel.m) to RGB
%   yLimits   - optional [min max] override for auto-scaling on the
%               value axis. Omit or pass [] for auto. (No xLimits
%               parameter - the x-axis here is categorical bar
%               positions, not a continuous quantity to cut.)
%
%   Returns uCombos, the combo labels in the order plotted (bar 1, 2, 3,
%   ...) so callers can add aligned overlays (e.g. significance brackets)
%   without recomputing the same ordering independently.

    if nargin < 6
        yLimits = [];
    end

    cla(ax);
    hold(ax, 'on');

    hasTreatmentCol = ismember('Treatment', dataTable.Properties.VariableNames);

    comboLabels = strings(height(dataTable), 1);
    for i = 1:height(dataTable)
        if hasTreatmentCol
            comboLabels(i) = curveComboLabel(dataTable.Group(i), dataTable.Treatment(i));
        else
            comboLabels(i) = curveComboLabel(dataTable.Group(i));
        end
    end
    uCombos = sortByConcentration(comboLabels);

    for k = 1:numel(uCombos)
        vals = dataTable.(valueCol)(comboLabels == uCombos(k));
        m = mean(vals);
        sd = std(vals);
        rgb = colorMap(char(uCombos(k)));

        bar(ax, k, m, 'FaceColor', rgb, 'EdgeColor', 'none', ...
            'BarWidth', 0.6, 'HandleVisibility', 'off');
        if numel(vals) > 1
            errorbar(ax, k, m, sd, 'Color', 'k', 'LineStyle', 'none', ...
                'LineWidth', 1.2, 'CapSize', 8, 'HandleVisibility', 'off');
        end

        jitterX = k + (rand(size(vals)) - 0.5) * 0.25;
        scatter(ax, jitterX, vals, 30, [0.15 0.15 0.15], 'filled', ...
            'MarkerFaceAlpha', 0.6, 'HandleVisibility', 'off');
    end

    xticks(ax, 1:numel(uCombos));
    xticklabels(ax, cellstr(uCombos));
    xtickangle(ax, 30);
    xlabel(ax, 'Group / Treatment');
    ylabel(ax, yLabelStr);
    title(ax, ['Summary Data: ' yLabelStr]);
    grid(ax, 'on');
    box(ax, 'on');
    hold(ax, 'off');

    % Explicit light styling: don't rely on the figure/desktop theme,
    % which can flip this to a dark background and make the near-black
    % error bars and data-point markers above effectively invisible.
    ax.Color = 'white';
    ax.XColor = 'k';
    ax.YColor = 'k';
    ax.GridColor = [0.15 0.15 0.15];
    ax.GridAlpha = 0.3;
    ax.Title.Color = 'k';
    applyPlotFontSizes(ax);

    tightenAxes(ax);

    if ~isempty(yLimits)
        ylim(ax, yLimits);
    end
end
