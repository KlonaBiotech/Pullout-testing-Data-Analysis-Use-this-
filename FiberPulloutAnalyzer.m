classdef FiberPulloutAnalyzer < matlab.apps.AppBase
    % FIBERPULLOUTANALYZER  One-window replacement for the manual
    % CSV -> Excel -> graphing tool -> Prism workflow.
    %
    % Launch with:   app = FiberPulloutAnalyzer;
    %
    % Accepted data files: .csv, .tsv, .xlsx, .xls (any mix, any folder
    % depth under the folder you Browse to).
    %
    % "Browse" selects the top-level data folder - every matching file
    % anywhere underneath it (nested however you like) is picked up
    % automatically; you do not need to point it at an individual test.
    %
    % Requires: Statistics and Machine Learning Toolbox
    % (anova1, anovan, kruskalwallis, multcompare, tinv, norminv, normcdf)
    % Normality testing uses shapiroWilkTest.m (bundled), a from-formula
    % implementation of the Shapiro-Wilk test (Royston 1995 approximation,
    % valid from n=3), since it isn't built into the toolbox - see that
    % file for validation notes. daPearsonTest.m (D'Agostino-Pearson) is
    % also bundled as a validated alternative but isn't called by default.
    % boxchart requires R2020b+; falls back gracefully on older releases.

    properties (Access = public)
        UIFigure          matlab.ui.Figure
        SetupPanel        matlab.ui.container.Panel
        PathLabel         matlab.ui.control.Label
        PathEditField     matlab.ui.control.EditField
        BrowseButton      matlab.ui.control.Button
        TieRuleLabel      matlab.ui.control.Label
        TieRuleDropDown   matlab.ui.control.DropDown
        AnovaLabel        matlab.ui.control.Label
        AnovaDropDown     matlab.ui.control.DropDown
        TreatLabel        matlab.ui.control.Label
        TreatEditField    matlab.ui.control.EditField
        MinNLabel         matlab.ui.control.Label
        MinNEditField     matlab.ui.control.NumericEditField
        RunButton         matlab.ui.control.Button
        ExportButton      matlab.ui.control.Button
        PopOutButton      matlab.ui.control.Button
        ExportGraphsButton matlab.ui.control.Button
        CumulativeLogLabel matlab.ui.control.Label
        CumulativeLogEditField matlab.ui.control.EditField
        CumulativeLogBrowseButton matlab.ui.control.Button
        AxisLimitsLabel   matlab.ui.control.Label
        XLimLabel         matlab.ui.control.Label
        XLimEditField     matlab.ui.control.EditField
        YLimLabel         matlab.ui.control.Label
        YLimEditField     matlab.ui.control.EditField
        BarChartLimitsLabel matlab.ui.control.Label
        ForceYLimLabel    matlab.ui.control.Label
        ForceYLimEditField matlab.ui.control.EditField
        DispYLimLabel     matlab.ui.control.Label
        DispYLimEditField matlab.ui.control.EditField
        LogLabel          matlab.ui.control.Label
        LogTextArea       matlab.ui.control.TextArea

        ResultsTable      matlab.ui.control.Table
        CurvesAxes        matlab.ui.control.UIAxes
        StatsAxes         matlab.ui.control.UIAxes
        StatsSummaryLabel matlab.ui.control.Label
        StatsSummaryArea  matlab.ui.control.TextArea
    end

    properties (Access = private)
        Data % struct: ResultsTable, Curves, Log, StatsResults, RootFolder
    end

    methods (Access = private)

        function limits = parseAxisLimitField(app, fieldValue)
            % Parses a "min,max" text field into a [min max] vector, or []
            % if blank (meaning auto-scale). Malformed input (not exactly
            % two numbers, or min>=max) is treated as blank/auto with a
            % logged warning, rather than silently applying something
            % wrong or crashing the plot.
            str = strtrim(fieldValue);
            if isempty(str)
                limits = [];
                return;
            end
            parts = strsplit(str, ',');
            nums = str2double(parts);
            if numel(nums) ~= 2 || any(isnan(nums)) || nums(1) >= nums(2)
                app.appendLog(sprintf( ...
                    'Ignoring axis limit "%s" - expected two numbers as "min,max" with min < max. Using auto-scale instead.', ...
                    str));
                limits = [];
                return;
            end
            limits = nums;
        end

        function appendLog(app, msg)
            existing = app.LogTextArea.Value;
            if isequal(existing, {''})
                existing = {};
            end
            timestamp = datestr(now, 'HH:MM:SS'); %#ok<TNOW1,DATST>
            app.LogTextArea.Value = [existing; {sprintf('[%s] %s', timestamp, msg)}];
            drawnow;
        end

        function BrowseButtonPushed(app, ~)
            folder = uigetdir(pwd, 'Select fiber pullout tests root folder (BioDrive)');
            if folder ~= 0
                app.PathEditField.Value = folder;
            end
        end

        function RunButtonPushed(app, ~)
            rootFolder = strtrim(app.PathEditField.Value);
            if isempty(rootFolder) || ~isfolder(rootFolder)
                uialert(app.UIFigure, 'Please select a valid data folder first.', 'No folder selected');
                return;
            end

            app.RunButton.Enable = 'off';
            app.appendLog('Starting analysis...');

            switch app.TieRuleDropDown.Value
                case 'Last (default)'
                    tieRule = 'last';
                otherwise
                    tieRule = 'first';
            end

            try
                [resultsTable, curves, procLog] = analyzeAllTestsByFilename(rootFolder, tieRule);
            catch ME
                app.appendLog(['ERROR during batch processing: ' ME.message]);
                app.RunButton.Enable = 'on';
                return;
            end

            for i = 1:numel(procLog)
                app.appendLog(procLog{i});
            end

            if isempty(resultsTable)
                app.appendLog('No valid tests found. Check the folder structure.');
                app.RunButton.Enable = 'on';
                return;
            end

            app.appendLog(sprintf('Processed %d tests across %d groups.', ...
                height(resultsTable), numel(unique(resultsTable.Group))));

            % Populate results table
            app.ResultsTable.Data = resultsTable;

            % Build one color map, shared by the embedded plots, the
            % pop-out figures, and the exported graphs, so a given
            % Group/Treatment combo is always the same color everywhere.
            comboLabels = strings(numel(curves), 1);
            for i = 1:numel(curves)
                comboLabels(i) = curveComboLabel(curves(i).Group, curves(i).Treatment);
            end
            colorMap = assignCurveColors(comboLabels);
            app.Data.ColorMap = colorMap;

            % Plot overlaid force-displacement curves, colored by group
            app.plotCurves(curves);

            % Stats
            switch app.AnovaDropDown.Value
                case 'One-way'
                    anovaMode = 'oneway';
                case 'Two-way'
                    anovaMode = 'twoway';
                otherwise
                    anovaMode = 'auto';
            end
            treatmentVar = strtrim(app.TreatEditField.Value);
            minN = app.MinNEditField.Value;

            try
                statsResults = runStatsPipeline(resultsTable, anovaMode, treatmentVar, minN);
            catch ME
                app.appendLog(['ERROR during stats: ' ME.message]);
                app.RunButton.Enable = 'on';
                return;
            end

            app.plotStats(resultsTable, statsResults);
            app.displayStatsSummary(statsResults);

            app.Data.RootFolder = rootFolder;
            app.Data.ResultsTable = resultsTable;
            app.Data.Curves = curves;
            app.Data.StatsResults = statsResults;

            app.appendLog('Done.');
            app.RunButton.Enable = 'on';
        end

        function plotCurves(app, curves)
            xLimits = app.parseAxisLimitField(app.XLimEditField.Value);
            yLimits = app.parseAxisLimitField(app.YLimEditField.Value);
            drawCurvesPlot(app.CurvesAxes, curves, app.Data.ColorMap, xLimits, yLimits);
        end

        function plotStats(app, resultsTable, statsResults)
            forceYLimits = app.parseAxisLimitField(app.ForceYLimEditField.Value);
            uCombos = drawSummaryBarChart(app.StatsAxes, resultsTable, 'PeakForce_N', ...
                'Peak Pull Out Force (N)', app.Data.ColorMap, forceYLimits);
            xlabel(app.StatsAxes, 'Group / Treatment');

            % Significance brackets only when combo labels equal plain
            % Group labels (i.e. every row's Treatment is 'none') - that's
            % the one case where PostHoc's Group-level pairs line up
            % exactly with the bars actually drawn. Otherwise the full
            % pairwise breakdown is in the Stats Summary text instead;
            % overlaying brackets for combos post-hoc wasn't run on would
            % be misleading rather than clearer.
            allNoTreatment = all(resultsTable.Treatment == "none");
            if allNoTreatment && height(statsResults.PostHoc) <= 10
                app.addSignificanceBrackets(statsResults, cellstr(uCombos));
            end

            title(app.StatsAxes, sprintf('%s: %s', statsResults.Test, app.formatPValues(statsResults)), ...
                'Interpreter', 'none');
        end

        function addSignificanceBrackets(app, statsResults, groupOrder)
            sig = statsResults.PostHoc(statsResults.PostHoc.pValue < 0.05, :);
            if isempty(sig)
                return;
            end

            yl = ylim(app.StatsAxes);
            yRange = yl(2) - yl(1);
            baseY = yl(2) + 0.08 * yRange;
            step = 0.10 * yRange;

            hold(app.StatsAxes, 'on');
            for i = 1:height(sig)
                x1 = find(strcmp(groupOrder, sig.Group1(i)), 1);
                x2 = find(strcmp(groupOrder, sig.Group2(i)), 1);
                if isempty(x1) || isempty(x2)
                    continue;
                end
                y = baseY + (i - 1) * step;
                pv = sig.pValue(i);
                if pv < 0.001
                    starLabel = '***';
                elseif pv < 0.01
                    starLabel = '**';
                else
                    starLabel = '*';
                end
                plot(app.StatsAxes, [x1 x2], [y y], 'Color', 'k', 'LineWidth', 1, 'HandleVisibility', 'off');
                text(app.StatsAxes, (x1 + x2) / 2, y, starLabel, ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 11);
            end
            hold(app.StatsAxes, 'off');
            ylim(app.StatsAxes, [yl(1), baseY + height(sig) * step + 0.05 * yRange]);
        end

        function displayStatsSummary(app, statsResults)
            lines_ = {};
            DIVIDER = repmat('-', 1, 78);

            % --- Fallback warning, if the requested test couldn't be run ---
            if isfield(statsResults, 'Warning') && ~isempty(statsResults.Warning)
                lines_{end+1} = '*** NOTE ***';
                lines_{end+1} = app.wrapText(statsResults.Warning, 78);
                lines_{end+1} = '';
            end

            % --- Descriptive statistics (aligned table) ---
            % Both peak force AND displacement-at-peak in one table, so
            % there's never a manual copy/combine step (and the
            % transcription-error risk that comes with it) between this
            % and a slide/report.
            lines_{end+1} = 'DESCRIPTIVE STATISTICS';
            lines_{end+1} = DIVIDER;
            lines_{end+1} = sprintf('%-12s %4s %11s %11s %13s %13s', ...
                'Group', 'n', 'Mean Peak F', 'SD Peak F', 'Mean Disp', 'SD Disp');
            lines_{end+1} = sprintf('%-12s %4s %11s %11s %13s %13s', ...
                '', '', '(N)', '(N)', 'at Peak (mm)', 'at Peak (mm)');
            d = statsResults.Descriptives;
            for i = 1:height(d)
                lines_{end+1} = sprintf('%-12s %4d %11.4f %11.4f %13.4f %13.4f', ...
                    d.Group(i), d.N(i), d.MeanPeakForce_N(i), d.SDPeakForce_N(i), ...
                    d.MeanDispAtPeak_mm(i), d.SDDispAtPeak_mm(i)); %#ok<AGROW>
            end
            lines_{end+1} = '';
            lines_{end+1} = '(SEM and 95% CI for both measures are in the exported descriptive_statistics.csv)';
            lines_{end+1} = '';

            % --- Normality (aligned table) ---
            lines_{end+1} = 'NORMALITY  (Shapiro-Wilk test, alpha=0.05)';
            lines_{end+1} = DIVIDER;
            nrm = statsResults.Normality;
            hasTreatmentCol = any(strlength(nrm.Treatment) > 0);
            if hasTreatmentCol
                lines_{end+1} = sprintf('%-12s %-12s %4s %10s %10s %s', ...
                    'Group', 'Treatment', 'n', 'W', 'p-value', 'Result');
            else
                lines_{end+1} = sprintf('%-12s %4s %10s %10s %s', ...
                    'Group', 'n', 'W', 'p-value', 'Result');
            end
            for i = 1:height(nrm)
                if isnan(nrm.PValue(i))
                    wStr = 'n/a';
                    pStr = 'n/a';
                else
                    wStr = sprintf('%.4f', nrm.Statistic(i));
                    pStr = sprintf('%.4f', nrm.PValue(i));
                end
                if hasTreatmentCol
                    lines_{end+1} = sprintf('%-12s %-12s %4d %10s %10s %s', ...
                        nrm.Group(i), nrm.Treatment(i), nrm.N(i), wStr, pStr, nrm.Result(i)); %#ok<AGROW>
                else
                    lines_{end+1} = sprintf('%-12s %4d %10s %10s %s', ...
                        nrm.Group(i), nrm.N(i), wStr, pStr, nrm.Result(i)); %#ok<AGROW>
                end
            end
            lines_{end+1} = '';
            if statsResults.IsNormal
                lines_{end+1} = 'Result: all testable cells pass normality -> parametric branch.';
            else
                lines_{end+1} = 'Result: at least one cell fails normality -> non-parametric branch (Kruskal-Wallis).';
            end
            lines_{end+1} = '';

            % --- Main test ---
            lines_{end+1} = sprintf('MAIN TEST:  %s', statsResults.Test);
            lines_{end+1} = DIVIDER;
            if isfield(statsResults, 'pLabels') && numel(statsResults.p) == numel(statsResults.pLabels)
                for i = 1:numel(statsResults.p)
                    lines_{end+1} = sprintf('  %-14s p = %s', ...
                        [statsResults.pLabels{i} ':'], app.formatSinglePValue(statsResults.p(i))); %#ok<AGROW>
                end
            else
                lines_{end+1} = sprintf('  p-value: %s', app.formatSinglePValue(statsResults.p(1)));
            end
            lines_{end+1} = '';

            % --- Effect size ---
            if isfield(statsResults, 'EffectSize') && ~isempty(fieldnames(statsResults.EffectSize))
                lines_{end+1} = 'EFFECT SIZE';
                lines_{end+1} = DIVIDER;
                esFields = fieldnames(statsResults.EffectSize);
                for i = 1:numel(esFields)
                    lines_{end+1} = sprintf('  %-16s %.4f', [esFields{i} ':'], ...
                        statsResults.EffectSize.(esFields{i})); %#ok<AGROW>
                end
                lines_{end+1} = '';
            end

            % --- Post-hoc (sorted most-to-least significant, aligned table) ---
            if isfield(statsResults, 'PostHoc') && ~isempty(statsResults.PostHoc)
                lines_{end+1} = sprintf('POST-HOC PAIRWISE COMPARISONS  (%s)', statsResults.PostHocMethod);
                lines_{end+1} = DIVIDER;
                ph = sortrows(statsResults.PostHoc, 'pValue');
                lines_{end+1} = sprintf('%-10s %-14s %-14s %10s %10s %10s %5s', ...
                    'Factor', 'Group 1', 'Group 2', 'Mean Diff', 'p-value', '95% CI', 'Sig');
                nSig = 0;
                for i = 1:height(ph)
                    if ph.pValue(i) < 0.001
                        sigMark = '***'; nSig = nSig + 1;
                    elseif ph.pValue(i) < 0.01
                        sigMark = '**'; nSig = nSig + 1;
                    elseif ph.pValue(i) < 0.05
                        sigMark = '*'; nSig = nSig + 1;
                    else
                        sigMark = 'ns';
                    end
                    if isnan(ph.MeanDiff(i))
                        diffStr = 'n/a';
                        pStr = 'n/a';
                        ciStr = 'n/a';
                    else
                        diffStr = sprintf('%.4f', ph.MeanDiff(i));
                        pStr = sprintf('%.4f', ph.pValue(i));
                        ciStr = sprintf('[%.3f,%.3f]', ph.CI_Lower(i), ph.CI_Upper(i));
                    end
                    lines_{end+1} = sprintf('%-10s %-14s %-14s %10s %10s %10s %5s', ...
                        ph.Factor(i), ph.Group1(i), ph.Group2(i), diffStr, pStr, ciStr, sigMark); %#ok<AGROW>
                end
                lines_{end+1} = '';
                lines_{end+1} = sprintf('%d of %d comparisons significant at p<0.05.', nSig, height(ph));
            end

            app.StatsSummaryArea.Value = lines_;
        end

        function wrapped = wrapText(~, str, width)
            % Simple word-wrap for long warning messages in the fixed-width summary.
            words = strsplit(str, ' ');
            lineStr = '';
            wrapped = {};
            for i = 1:numel(words)
                candidate = strtrim([lineStr ' ' words{i}]);
                if strlength(candidate) > width && ~isempty(lineStr)
                    wrapped{end+1} = lineStr; %#ok<AGROW>
                    lineStr = words{i};
                else
                    lineStr = candidate;
                end
            end
            if ~isempty(lineStr)
                wrapped{end+1} = lineStr; %#ok<AGROW>
            end
            wrapped = strjoin(wrapped, newline);
        end

        function str = formatSinglePValue(~, pval)
            if isnan(pval)
                str = 'n/a';
            elseif pval < 0.0001
                str = sprintf('%.4g (< 0.0001)', pval);
            else
                str = sprintf('%.4f', pval);
            end
        end

        function str = formatPValues(~, statsResults)
            % Formats one or several labeled p-values into one display
            % string, e.g. "Group p=0.01, Treatment p=0.4".
            if isfield(statsResults, 'pLabels') && numel(statsResults.p) == numel(statsResults.pLabels)
                parts = cell(1, numel(statsResults.p));
                for i = 1:numel(statsResults.p)
                    parts{i} = sprintf('%s p=%.3g', statsResults.pLabels{i}, statsResults.p(i));
                end
                str = strjoin(parts, ', ');
            else
                str = sprintf('p = %.4g', statsResults.p(1));
            end
        end

        function ExportButtonPushed(app, ~)
            if isempty(app.Data) || ~isfield(app.Data, 'ResultsTable')
                uialert(app.UIFigure, 'Run an analysis first.', 'Nothing to export');
                return;
            end

            exportFolder = uigetdir(pwd, 'Select folder to save results into');
            if isequal(exportFolder, 0)
                return;
            end

            try
                csvPath = fullfile(exportFolder, 'peak_force_results.csv');
                writetable(app.Data.ResultsTable, csvPath);
                app.appendLog(['Saved: ' csvPath]);

                descPath = fullfile(exportFolder, 'descriptive_statistics.csv');
                writetable(app.Data.StatsResults.Descriptives, descPath);
                app.appendLog(['Saved: ' descPath]);

                normPath = fullfile(exportFolder, 'normality_results.csv');
                writetable(app.Data.StatsResults.Normality, normPath);
                app.appendLog(['Saved: ' normPath]);

                if ~isempty(app.Data.StatsResults.PostHoc)
                    postHocPath = fullfile(exportFolder, 'posthoc_comparisons.csv');
                    writetable(app.Data.StatsResults.PostHoc, postHocPath);
                    app.appendLog(['Saved: ' postHocPath]);
                end

                curvesPng = fullfile(exportFolder, 'force_displacement_curves.png');
                exportgraphics(app.CurvesAxes, curvesPng);
                app.appendLog(['Saved: ' curvesPng]);

                statsPng = fullfile(exportFolder, 'stats_summary_plot.png');
                exportgraphics(app.StatsAxes, statsPng);
                app.appendLog(['Saved: ' statsPng]);

                summaryPath = fullfile(exportFolder, 'stats_summary.txt');
                fid = fopen(summaryPath, 'w');
                summaryLines = app.StatsSummaryArea.Value;
                for i = 1:numel(summaryLines)
                    fprintf(fid, '%s\n', summaryLines{i});
                end
                fclose(fid);
                app.appendLog(['Saved: ' summaryPath]);

                uialert(app.UIFigure, 'Export complete.', 'Done', 'Icon', 'success');
            catch ME
                app.appendLog(['ERROR during export: ' ME.message]);
                uialert(app.UIFigure, ['Export failed: ' ME.message], 'Error');
            end
        end

        function CumulativeLogBrowseButtonPushed(app, ~)
            [file, folder] = uiputfile('*.csv', 'Select or create cumulative log file', 'cumulative_log.csv');
            if isequal(file, 0)
                return;
            end
            app.CumulativeLogEditField.Value = fullfile(folder, file);
        end

        function PopOutButtonPushed(app, ~)
            if isempty(app.Data) || ~isfield(app.Data, 'ResultsTable')
                uialert(app.UIFigure, 'Run an analysis first.', 'Nothing to show');
                return;
            end

            xLimits = app.parseAxisLimitField(app.XLimEditField.Value);
            yLimits = app.parseAxisLimitField(app.YLimEditField.Value);
            forceYLimits = app.parseAxisLimitField(app.ForceYLimEditField.Value);
            dispYLimits = app.parseAxisLimitField(app.DispYLimEditField.Value);

            % Native figure windows: full MATLAB toolbar (zoom, pan, data
            % cursor, File > Save As / Export) - not constrained to the
            % small embedded panels in the app itself.
            fig1 = figure('Name', 'All Individual Pull-Out Curves', 'NumberTitle', 'off');
            forceLightFigure(fig1);
            drawCurvesPlot(axes(fig1), app.Data.Curves, app.Data.ColorMap, xLimits, yLimits);

            fig2 = figure('Name', 'Mean Pull-Out Curves by Group', 'NumberTitle', 'off');
            forceLightFigure(fig2);
            drawMeanCurvesPlot(axes(fig2), app.Data.Curves, app.Data.ColorMap, xLimits, yLimits);

            fig3 = figure('Name', 'Summary Data - Peak Force', 'NumberTitle', 'off');
            forceLightFigure(fig3);
            drawSummaryBarChart(axes(fig3), app.Data.ResultsTable, 'PeakForce_N', ...
                'Peak Pull Out Force (N)', app.Data.ColorMap, forceYLimits);

            fig4 = figure('Name', 'Summary Data - Displacement at Peak', 'NumberTitle', 'off');
            forceLightFigure(fig4);
            drawSummaryBarChart(axes(fig4), app.Data.ResultsTable, 'DispAtPeak_mm', ...
                'Displacement at Peak (mm)', app.Data.ColorMap, dispYLimits);

            app.appendLog('Opened 4 full-size plot windows.');
        end

        function ExportGraphsButtonPushed(app, ~)
            if isempty(app.Data) || ~isfield(app.Data, 'ResultsTable')
                uialert(app.UIFigure, 'Run an analysis first.', 'Nothing to export');
                return;
            end

            exportFolder = uigetdir(pwd, 'Select folder to save full-size graphs into');
            if isequal(exportFolder, 0)
                return;
            end

            app.ExportGraphsButton.Enable = 'off';
            try
                resultsTable = app.Data.ResultsTable;
                curves = app.Data.Curves;
                colorMap = app.Data.ColorMap;
                xLimits = app.parseAxisLimitField(app.XLimEditField.Value);
                yLimits = app.parseAxisLimitField(app.YLimEditField.Value);
                forceYLimits = app.parseAxisLimitField(app.ForceYLimEditField.Value);
                dispYLimits = app.parseAxisLimitField(app.DispYLimEditField.Value);

                % Each graph is drawn fresh on its own full-size,
                % offscreen figure (not screenshotted from the small
                % embedded panels), then saved at high resolution - this
                % is what makes them big/crisp enough to drop straight
                % into a slide.
                app.exportOneGraph(@() drawSummaryBarChart(gca, resultsTable, 'PeakForce_N', ...
                    'Peak Pull Out Force (N)', colorMap, forceYLimits), ...
                    fullfile(exportFolder, '01_SummaryData_PeakForce.png'));

                app.exportOneGraph(@() drawSummaryBarChart(gca, resultsTable, 'DispAtPeak_mm', ...
                    'Displacement at Peak (mm)', colorMap, dispYLimits), ...
                    fullfile(exportFolder, '02_SummaryData_Displacement.png'));

                app.exportOneGraph(@() drawCurvesPlot(gca, curves, colorMap, xLimits, yLimits), ...
                    fullfile(exportFolder, '03_OverallResults_AllCurves.png'));

                app.exportOneGraph(@() drawMeanCurvesPlot(gca, curves, colorMap, xLimits, yLimits), ...
                    fullfile(exportFolder, '04_OverallResults_MeanCurves.png'));

                % One curve chart per Group/Treatment combo, matching the
                % "10 mM - No PT" style individual slides.
                comboLabels = strings(numel(curves), 1);
                for i = 1:numel(curves)
                    comboLabels(i) = curveComboLabel(curves(i).Group, curves(i).Treatment);
                end
                uCombos = sortByConcentration(comboLabels);
                for k = 1:numel(uCombos)
                    idx = find(comboLabels == uCombos(k));
                    safeName = matlab.lang.makeValidName(uCombos(k));
                    fileName = fullfile(exportFolder, sprintf('05_%02d_%s.png', k, safeName));
                    app.exportOneGraph(@() app.drawOneComboCurves(gca, curves(idx), xLimits, yLimits), fileName);
                end

                % Optional cumulative "All Data Points Thus Far" charts
                logPath = strtrim(app.CumulativeLogEditField.Value);
                if ~isempty(logPath)
                    cumulativeTable = updateAndLoadCumulativeLog(resultsTable, logPath);
                    app.appendLog(sprintf('Cumulative log updated: %s (n=%d rows total)', ...
                        logPath, height(cumulativeTable)));

                    cumComboLabels = strings(height(cumulativeTable), 1);
                    for i = 1:height(cumulativeTable)
                        cumComboLabels(i) = curveComboLabel(cumulativeTable.Group(i), cumulativeTable.Treatment(i));
                    end
                    cumColorMap = assignCurveColors(cumComboLabels);

                    app.exportOneGraph(@() drawSummaryBarChart(gca, cumulativeTable, 'PeakForce_N', ...
                        'Peak Pull Out Force (N)', cumColorMap, forceYLimits), ...
                        fullfile(exportFolder, '06_AllDataThusFar_PeakForce.png'));

                    app.exportOneGraph(@() drawSummaryBarChart(gca, cumulativeTable, 'DispAtPeak_mm', ...
                        'Displacement at Peak (mm)', cumColorMap, dispYLimits), ...
                        fullfile(exportFolder, '07_AllDataThusFar_Displacement.png'));
                end

                app.appendLog(['All graphs exported to: ' exportFolder]);
                uialert(app.UIFigure, 'Graph export complete.', 'Done', 'Icon', 'success');
            catch ME
                app.appendLog(['ERROR during graph export: ' ME.message]);
                uialert(app.UIFigure, ['Graph export failed: ' ME.message], 'Error');
            end
            app.ExportGraphsButton.Enable = 'on';
        end

        function exportOneGraph(~, drawFcn, filePath)
            % Draws one graph on a full-size (10x7in @ 200 DPI target),
            % offscreen figure via drawFcn, saves it, and closes it - even
            % if drawFcn errors partway through (onCleanup guarantees the
            % offscreen figure doesn't linger).
            fig = figure('Visible', 'off', 'Units', 'inches', 'Position', [1 1 10 7]);
            cleanupObj = onCleanup(@() close(fig, 'force')); %#ok<NASGU>
            forceLightFigure(fig);
            axes(fig);
            drawFcn();
            exportgraphics(fig, filePath, 'Resolution', 200);
        end

        function drawOneComboCurves(~, ax, curveSubset, xLimits, yLimits)
            % All individual curves for a single Group/Treatment combo,
            % labeled by TestID - matches the per-condition slide style
            % (e.g. "10 mM - No PT: individual force-displacement curves").
            %
            % Each sample gets its OWN distinct color here (not the shared
            % combo color used in the all-combos overview plots) - within
            % a single-combo view, distinguishing individual samples from
            % each other is the whole point, so they can't all be one color.
            if nargin < 4
                xLimits = [];
            end
            if nargin < 5
                yLimits = [];
            end

            cla(ax);
            hold(ax, 'on');

            testIDs = strings(numel(curveSubset), 1);
            for i = 1:numel(curveSubset)
                testIDs(i) = string(curveSubset(i).TestID);
            end
            sampleColorMap = assignCurveColors(testIDs);

            for i = 1:numel(curveSubset)
                rgb = sampleColorMap(char(testIDs(i)));
                plot(ax, curveSubset(i).Displacement, curveSubset(i).Load, ...
                    'Color', rgb, 'LineStyle', '-', 'LineWidth', 1.4, ...
                    'DisplayName', testIDs(i));
            end

            hold(ax, 'off');
            xlabel(ax, 'Displacement (mm)');
            ylabel(ax, 'Load (N)');
            comboTitle = curveComboLabel(curveSubset(1).Group, curveSubset(1).Treatment);
            title(ax, sprintf('%s: individual force-displacement curves', comboTitle));
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

        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 60 1300 780];
            app.UIFigure.Name = 'Fiber Pullout Analyzer - Klona Biotech';
            app.UIFigure.Color = 'white';
            try
                theme(app.UIFigure, 'light'); % no-op before R2025a; see forceLightFigure.m
            catch
            end

            % --- Setup panel (left column) ---
            app.SetupPanel = uipanel(app.UIFigure);
            app.SetupPanel.Title = 'Setup';
            app.SetupPanel.Position = [20 20 340 740];

            % Layout note: every Position below was computed
            % programmatically (top-down accumulation of exact row
            % heights + gaps, verified with zero overlaps) rather than
            % hand-picked, after a hand-picked version caused an overlap
            % bug (MinN row colliding with the Run/Export buttons and
            % Treatment field). Any future row inserted into this panel
            % should extend that same computation, not eyeball a gap.

            app.PathLabel = uilabel(app.SetupPanel);
            app.PathLabel.Position = [10 680 320 48];
            app.PathLabel.Text = ['Data folder (top-level BioDrive folder - Browse selects ' ...
                'this folder, every CSV/TSV/XLSX/XLS file under it, at any depth, is included):'];
            app.PathLabel.WordWrap = 'on';

            app.PathEditField = uieditfield(app.SetupPanel, 'text');
            app.PathEditField.Position = [10 656 240 24];

            app.BrowseButton = uibutton(app.SetupPanel, 'push');
            app.BrowseButton.Position = [260 656 60 24];
            app.BrowseButton.Text = 'Browse';
            app.BrowseButton.ButtonPushedFcn = createCallbackFcn(app, @BrowseButtonPushed, true);

            app.TieRuleLabel = uilabel(app.SetupPanel);
            app.TieRuleLabel.Position = [10 624 320 22];
            app.TieRuleLabel.Text = 'Tie-break rule (peak load plateaus):';

            app.TieRuleDropDown = uidropdown(app.SetupPanel);
            app.TieRuleDropDown.Items = {'Last (default)', 'First'};
            app.TieRuleDropDown.Position = [10 600 310 24];

            app.AnovaLabel = uilabel(app.SetupPanel);
            app.AnovaLabel.Position = [10 568 300 22];
            app.AnovaLabel.Text = 'ANOVA mode:';

            app.AnovaDropDown = uidropdown(app.SetupPanel);
            app.AnovaDropDown.Items = {'Auto-detect', 'One-way', 'Two-way'};
            app.AnovaDropDown.Position = [10 544 310 24];

            app.TreatLabel = uilabel(app.SetupPanel);
            app.TreatLabel.Position = [10 504 320 30];
            app.TreatLabel.Text = 'Treatment column name (auto-parsed; two-way only):';
            app.TreatLabel.WordWrap = 'on';

            app.TreatEditField = uieditfield(app.SetupPanel, 'text');
            app.TreatEditField.Position = [10 480 310 24];
            app.TreatEditField.Value = 'Treatment';
            app.TreatEditField.Placeholder = 'e.g. Treatment';

            app.MinNLabel = uilabel(app.SetupPanel);
            app.MinNLabel.Position = [10 446 230 22];
            app.MinNLabel.Text = 'Min n for normality test (>=3):';

            app.MinNEditField = uieditfield(app.SetupPanel, 'numeric');
            app.MinNEditField.Position = [245 446 65 24];
            app.MinNEditField.Value = 3;
            app.MinNEditField.Limits = [3 Inf];
            app.MinNEditField.RoundFractionalValues = 'on';

            app.RunButton = uibutton(app.SetupPanel, 'push');
            app.RunButton.Position = [10 404 150 32];
            app.RunButton.Text = 'Run Analysis';
            app.RunButton.BackgroundColor = [0.4 0.7 0.4];
            app.RunButton.ButtonPushedFcn = createCallbackFcn(app, @RunButtonPushed, true);

            app.ExportButton = uibutton(app.SetupPanel, 'push');
            app.ExportButton.Position = [170 404 150 32];
            app.ExportButton.Text = 'Export Results';
            app.ExportButton.ButtonPushedFcn = createCallbackFcn(app, @ExportButtonPushed, true);

            app.PopOutButton = uibutton(app.SetupPanel, 'push');
            app.PopOutButton.Position = [10 364 150 32];
            app.PopOutButton.Text = 'Pop Out Plots';
            app.PopOutButton.ButtonPushedFcn = createCallbackFcn(app, @PopOutButtonPushed, true);

            app.ExportGraphsButton = uibutton(app.SetupPanel, 'push');
            app.ExportGraphsButton.Position = [170 364 150 32];
            app.ExportGraphsButton.Text = 'Export Full-Size Graphs';
            app.ExportGraphsButton.ButtonPushedFcn = createCallbackFcn(app, @ExportGraphsButtonPushed, true);

            app.CumulativeLogLabel = uilabel(app.SetupPanel);
            app.CumulativeLogLabel.Position = [10 320 320 34];
            app.CumulativeLogLabel.Text = ['Cumulative log CSV (optional - adds an "All Data Points ' ...
                'Thus Far" chart to the exported graphs, tracking every run logged to this file):'];
            app.CumulativeLogLabel.WordWrap = 'on';

            app.CumulativeLogEditField = uieditfield(app.SetupPanel, 'text');
            app.CumulativeLogEditField.Position = [10 296 240 24];
            app.CumulativeLogEditField.Placeholder = 'leave blank to skip';

            app.CumulativeLogBrowseButton = uibutton(app.SetupPanel, 'push');
            app.CumulativeLogBrowseButton.Position = [260 296 60 24];
            app.CumulativeLogBrowseButton.Text = 'Browse';
            app.CumulativeLogBrowseButton.ButtonPushedFcn = createCallbackFcn(app, @CumulativeLogBrowseButtonPushed, true);

            app.AxisLimitsLabel = uilabel(app.SetupPanel);
            app.AxisLimitsLabel.Position = [10 266 320 20];
            app.AxisLimitsLabel.Text = 'Axis limits for curve plots (optional, blank = auto):';

            app.XLimLabel = uilabel(app.SetupPanel);
            app.XLimLabel.Position = [10 242 18 22];
            app.XLimLabel.Text = 'X:';

            app.XLimEditField = uieditfield(app.SetupPanel, 'text');
            app.XLimEditField.Position = [28 242 130 24];
            app.XLimEditField.Placeholder = 'e.g. 0,6';

            app.YLimLabel = uilabel(app.SetupPanel);
            app.YLimLabel.Position = [170 242 18 22];
            app.YLimLabel.Text = 'Y:';

            app.YLimEditField = uieditfield(app.SetupPanel, 'text');
            app.YLimEditField.Position = [188 242 130 24];
            app.YLimEditField.Placeholder = 'e.g. 0,1';

            app.BarChartLimitsLabel = uilabel(app.SetupPanel);
            app.BarChartLimitsLabel.Position = [10 214 320 20];
            app.BarChartLimitsLabel.Text = 'Bar chart Y-axis limits (optional, blank = auto):';

            app.ForceYLimLabel = uilabel(app.SetupPanel);
            app.ForceYLimLabel.Position = [10 190 42 22];
            app.ForceYLimLabel.Text = 'Force:';

            app.ForceYLimEditField = uieditfield(app.SetupPanel, 'text');
            app.ForceYLimEditField.Position = [54 190 105 24];
            app.ForceYLimEditField.Placeholder = 'e.g. 0,0.5';

            app.DispYLimLabel = uilabel(app.SetupPanel);
            app.DispYLimLabel.Position = [170 190 36 22];
            app.DispYLimLabel.Text = 'Disp:';

            app.DispYLimEditField = uieditfield(app.SetupPanel, 'text');
            app.DispYLimEditField.Position = [208 190 110 24];
            app.DispYLimEditField.Placeholder = 'e.g. 0,2';

            app.LogLabel = uilabel(app.SetupPanel);
            app.LogLabel.Position = [10 158 300 22];
            app.LogLabel.Text = 'Status / Log:';

            app.LogTextArea = uitextarea(app.SetupPanel);
            app.LogTextArea.Position = [10 10 310 148];
            app.LogTextArea.Editable = 'off';

            % --- Right column: table, curves, stats ---
            app.ResultsTable = uitable(app.UIFigure);
            app.ResultsTable.Position = [380 500 900 260];
            app.ResultsTable.ColumnName = {'Test ID', 'Group (conc.)', 'Treatment', 'Peak Force (N)', 'Disp at Peak (mm)'};

            app.CurvesAxes = uiaxes(app.UIFigure);
            app.CurvesAxes.Position = [380 260 440 220];

            app.StatsAxes = uiaxes(app.UIFigure);
            app.StatsAxes.Position = [840 260 440 220];

            app.StatsSummaryLabel = uilabel(app.UIFigure);
            app.StatsSummaryLabel.Position = [380 225 300 22];
            app.StatsSummaryLabel.Text = 'Stats summary:';

            app.StatsSummaryArea = uitextarea(app.UIFigure);
            app.StatsSummaryArea.Position = [380 20 900 200];
            app.StatsSummaryArea.Editable = 'off';
            app.StatsSummaryArea.FontName = 'Consolas'; % monospace so table columns align

            app.UIFigure.Visible = 'on';
        end
    end

    methods (Access = public)
        function app = FiberPulloutAnalyzer
            createComponents(app);
            registerApp(app, app.UIFigure);
            app.Data = struct();
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end
end
