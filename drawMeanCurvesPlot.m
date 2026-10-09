function drawMeanCurvesPlot(ax, curves, colorMap, xLimits, yLimits)
%DRAWMEANCURVESPLOT Plot the mean force-displacement curve per Group/
%   Treatment combo, with a shaded +/- SD band, matching the "Mean
%   Pull-Out Curves by Group" style.
%
%   DRAWMEANCURVESPLOT(ax, curves, colorMap, xLimits, yLimits)
%
%   xLimits, yLimits - optional [min max] overrides for auto-scaling
%   (e.g. cut off a long displacement tail). Omit or pass [] for auto.
%
%   Curves within a combo are interpolated onto a common displacement
%   grid before averaging (since raw tests rarely share identical
%   displacement sampling or total length). Points beyond an individual
%   curve's own displacement range are left as NaN (no extrapolation)
%   and excluded from that grid point's mean/SD via 'omitnan', so the
%   shaded band and the number of curves contributing narrows naturally
%   as shorter tests drop out - it is not a display artifact.

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
        combo = uCombos(k);
        idx = find(comboLabels == combo);
        if isempty(idx)
            continue;
        end
        rgb = colorMap(char(combo));

        maxDisp = 0;
        for j = 1:numel(idx)
            maxDisp = max(maxDisp, max(curves(idx(j)).Displacement));
        end
        gridX = linspace(0, maxDisp, 200);

        interpMat = NaN(numel(idx), numel(gridX));
        for j = 1:numel(idx)
            i = idx(j);
            d = curves(i).Displacement;
            l = curves(i).Load;
            [d, sortIdx] = sort(d);
            l = l(sortIdx);
            [d, uniqueIdx] = unique(d); % interp1 requires strictly unique x
            l = l(uniqueIdx);
            interpMat(j, :) = interp1(d, l, gridX, 'linear', NaN);
        end

        meanCurve = mean(interpMat, 1, 'omitnan');
        stdCurve = std(interpMat, 0, 1, 'omitnan');
        nPerPoint = sum(~isnan(interpMat), 1);
        validMask = nPerPoint > 0;

        gx = gridX(validMask);
        mc = meanCurve(validMask);
        sc = stdCurve(validMask);
        sc(isnan(sc)) = 0; % single-curve points have no SD to shade

        upper = mc + sc;
        lower = mc - sc;
        fill(ax, [gx, fliplr(gx)], [upper, fliplr(lower)], rgb, ...
            'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');

        plot(ax, gx, mc, 'Color', rgb, 'LineStyle', '-', 'LineWidth', 2, ...
            'DisplayName', sprintf('%s (n=%d)', combo, numel(idx)));
    end

    hold(ax, 'off');
    xlabel(ax, 'Displacement (mm)');
    ylabel(ax, 'Load (N)');
    title(ax, 'Mean Pull-Out Curves by Group (shaded = +/- SD)');
    grid(ax, 'on');
    box(ax, 'on');
    lgd = legend(ax, 'show', 'Location', 'best');

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

    if ~isempty(xLimits)
        xlim(ax, xLimits);
    end
    if ~isempty(yLimits)
        ylim(ax, yLimits);
    end
end
