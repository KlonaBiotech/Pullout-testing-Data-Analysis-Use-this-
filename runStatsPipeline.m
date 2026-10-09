function statsResults = runStatsPipeline(resultsTable, anovaMode, treatmentVar, minN)
%RUNSTATSPIPELINE Descriptive stats -> normality check -> ANOVA/Kruskal-Wallis
%   -> post-hoc multiple comparisons, all with named, citable methods.
%
%   statsResults = RUNSTATSPIPELINE(resultsTable, anovaMode, treatmentVar, minN)
%
%   anovaMode    - 'auto', 'oneway', or 'twoway'.
%                  'auto' uses two-way only if treatmentVar is a valid
%                  column AND has more than one distinct value present;
%                  otherwise one-way.
%   treatmentVar - name of the second-factor column (e.g. 'Treatment'),
%                  only used for two-way ANOVA.
%   minN         - minimum sample size per cell to attempt a normality
%                  test at all; cells smaller than this report "Not
%                  tested" rather than a number. Default 3 (the smallest
%                  n Shapiro-Wilk can mathematically handle - see below).
%                  Configurable because what counts as "enough data to
%                  bother testing" reasonably differs across studies.
%
%   METHODS USED (so results are reproducible/citable):
%     Normality  : Shapiro-Wilk test (shapiroWilkTest.m, Royston 1995
%                  AS R94 approximation) - GraphPad Prism's own
%                  recommended default normality test. Valid from n=3
%                  up (unlike D'Agostino-Pearson, daPearsonTest.m, also
%                  bundled - its formula divides by n-3 and is
%                  undefined below n=8; kept in the codebase as a
%                  validated alternative but not called by default).
%     One-way    : anova1 (classic one-way ANOVA).
%     Two-way    : anovan with 'model','interaction','sstype',3
%                  (Type III sum of squares - matches GraphPad Prism's
%                  default for two-way ANOVA; explicit here because SS
%                  type changes results for unbalanced designs).
%     Non-parametric: kruskalwallis (one-way on ranks) - note this is a
%                  group-comparison test, not a normality test; it's
%                  what peak-force/displacement get compared with when
%                  Shapiro-Wilk says the data isn't normal.
%     Post-hoc   : Tukey-Kramer HSD for ANOVA branches (multcompare
%                  default), Dunn-Sidak for the Kruskal-Wallis branch
%                  (multcompare 'CriticalValueType','dunn-sidak', the
%                  standard rank-based post-hoc with family-wise
%                  correction). All pairwise, not just vs. control.
%     Effect size: eta-squared (one-way) / partial eta-squared (two-way,
%                  per term) computed from the ANOVA sum-of-squares table.

    if nargin < 3
        treatmentVar = '';
    end
    if nargin < 4 || isempty(minN)
        minN = 3;
    end
    if minN < 3
        minN = 3; % hard mathematical floor - shapiroWilkTest.m cannot compute
        % a meaningful statistic below n=3 (need at least 3 points for the
        % order-statistics correlation the test is built on); silently
        % letting a smaller minN through would make comparisons against
        % its NaN result misreport as "Normal" rather than "not tested".
    end

    % ---------- Determine the effective comparison variable ----------
    % Normally Group (e.g. concentration or fiber type) drives the
    % one-way comparison, with Treatment as an optional second factor.
    % But if Group is CONSTANT across the whole dataset (e.g. one fiber
    % type tested with two treatments) while Treatment varies, Group
    % alone has nothing to compare - Treatment is the real variable of
    % interest here, and reporting "not enough groups" would be wrong
    % when a perfectly good comparison exists on Treatment. Swap roles
    % in that specific case.
    hasTreatmentCol = ~isempty(treatmentVar) && ...
        ismember(treatmentVar, resultsTable.Properties.VariableNames);
    treatmentVaries = hasTreatmentCol && numel(unique(resultsTable.(treatmentVar))) > 1;
    rawGroupCount = numel(unique(resultsTable.Group));

    swappedGroupForTreatment = rawGroupCount < 2 && treatmentVaries;
    if swappedGroupForTreatment
        effectiveGroupCol = resultsTable.(treatmentVar);
        groupFactorName = treatmentVar;
    else
        effectiveGroupCol = resultsTable.Group;
        groupFactorName = 'Group';
    end

    groups = sortByConcentration(effectiveGroupCol);
    nG = numel(groups);

    % ---------- Descriptive statistics per Group+Treatment combo ----------
    % (n, mean, SD, SEM, 95% CI via t-distribution, for BOTH peak force
    % and displacement-at-peak - reported regardless of branch, since
    % Prism shows these no matter which test is used. Computing both in
    % one table here, rather than requiring Peak Force and Displacement
    % numbers to be assembled separately and combined by hand afterward,
    % is deliberate - that manual combination step is exactly where a
    % transcription error can (and did) creep in.)
    %
    % IMPORTANT: grouped by Group+Treatment COMBO here (e.g. "Trauer,
    % woEDC-NHS" and plain "Trauer" are separate rows), matching exactly
    % what the bar charts/curve legends show - NOT by Group alone. Group
    % is used alone for the actual ANOVA Group-factor logic elsewhere in
    % this file (correct - Group and Treatment are separate factors
    % there), but pooling every Treatment level into one Descriptives row
    % per Group would silently merge conditions that are shown as
    % distinct everywhere else in the app, hiding real differences
    % between e.g. a crosslinked and an uncrosslinked control.
    hasTreatmentColForDesc = ismember('Treatment', resultsTable.Properties.VariableNames);
    if hasTreatmentColForDesc
        descCombos = unique(resultsTable(:, {'Group', 'Treatment'}), 'rows');
        comboLabelsForDescSort = strings(height(descCombos), 1);
        for ci = 1:height(descCombos)
            comboLabelsForDescSort(ci) = curveComboLabel(descCombos.Group(ci), descCombos.Treatment(ci));
        end
        [~, descSortOrder] = ismember(sortByConcentration(comboLabelsForDescSort), comboLabelsForDescSort);
        descCombos = descCombos(descSortOrder, :);
        descLabels = comboLabelsForDescSort(descSortOrder);
    else
        descCombos = table(groups, 'VariableNames', {'Group'});
        descLabels = groups;
    end

    nDesc = height(descCombos);
    descRows = cell(nDesc, 10);
    for i = 1:nDesc
        if hasTreatmentColForDesc
            mask = resultsTable.Group == descCombos.Group(i) & resultsTable.Treatment == descCombos.Treatment(i);
        else
            mask = resultsTable.Group == descCombos.Group(i);
        end
        peakVals = resultsTable.PeakForce_N(mask);
        dispVals = resultsTable.DispAtPeak_mm(mask);
        n = numel(peakVals);

        meanPeak = mean(peakVals);
        sdPeak = std(peakVals);
        semPeak = sdPeak / sqrt(n);

        meanDisp = mean(dispVals);
        sdDisp = std(dispVals);
        semDisp = sdDisp / sqrt(n);

        if n >= 2
            tCrit = tinv(0.975, n - 1);
            ciPeak = tCrit * semPeak;
            ciDisp = tCrit * semDisp;
        else
            ciPeak = NaN;
            ciDisp = NaN;
        end

        descRows(i, :) = {descLabels(i), n, meanPeak, sdPeak, semPeak, ciPeak, ...
            meanDisp, sdDisp, semDisp, ciDisp};
    end
    statsResults.Descriptives = cell2table(descRows, 'VariableNames', ...
        {'Group', 'N', 'MeanPeakForce_N', 'SDPeakForce_N', 'SEMPeakForce_N', 'CI95PeakForce_N', ...
         'MeanDispAtPeak_mm', 'SDDispAtPeak_mm', 'SEMDispAtPeak_mm', 'CI95DispAtPeak_mm'});

    % ---------- Normality (D'Agostino-Pearson omnibus K2 test), checked
    % at the finest cell level (per Group x Treatment combination, or per
    % Group if there's no treatment factor). Requires n>=8 per cell; this
    % is a stricter minimum than most cells in a small pilot dataset will
    % have, so "not enough data to test" is an expected, honest result -
    % not an error - until there's more replication. ----------
    isNormal = true;
    normRows = {}; % Group, Treatment, N, Statistic, PValue, Result (cell rows, built up then converted to a table)

    if treatmentVaries
        combos = unique(resultsTable(:, {'Group', treatmentVar}), 'rows');
        comboLabelsForSort = strings(height(combos), 1);
        for ci = 1:height(combos)
            comboLabelsForSort(ci) = curveComboLabel(combos.Group(ci), combos.(treatmentVar)(ci));
        end
        [~, sortOrder] = ismember(sortByConcentration(comboLabelsForSort), comboLabelsForSort);
        combos = combos(sortOrder, :);
        for i = 1:height(combos)
            mask = resultsTable.Group == combos.Group(i) & ...
                resultsTable.(treatmentVar) == combos.(treatmentVar)(i);
            vals = resultsTable.PeakForce_N(mask);
            [normRows, isNormal] = appendNormalityRow(normRows, isNormal, ...
                combos.Group(i), combos.(treatmentVar)(i), vals, minN);
        end
    else
        for i = 1:nG
            vals = resultsTable.PeakForce_N(resultsTable.Group == groups(i));
            [normRows, isNormal] = appendNormalityRow(normRows, isNormal, groups(i), "", vals, minN);
        end
    end

    statsResults.Normality = cell2table(normRows, ...
        'VariableNames', {'Group', 'Treatment', 'N', 'Statistic', 'PValue', 'Result'});
    statsResults.IsNormal = isNormal;

    % hasTreatment here means "is Treatment a genuine second factor to
    % cross with Group" - false when Treatment was promoted to be the
    % sole comparison variable (swappedGroupForTreatment), since in that
    % case Group has no variation left to cross it with.
    hasTreatment = treatmentVaries && ~swappedGroupForTreatment;

    if strcmpi(anovaMode, 'auto')
        if hasTreatment
            anovaMode = 'twoway';
        else
            anovaMode = 'oneway';
        end
    end

    statsResults.Warning = '';
    if swappedGroupForTreatment
        statsResults.Warning = sprintf(['Group is constant ("%s") across this dataset, so %s ' ...
            '(%s) was used as the comparison variable instead - there was nothing to compare on ' ...
            'Group alone.'], string(resultsTable.Group(1)), groupFactorName, ...
            strjoin(cellstr(unique(effectiveGroupCol)), ' vs '));
    end

    if nG < 2
        statsResults.Test = 'Not enough groups for a comparison (need >= 2)';
        statsResults.p = NaN;
        statsResults.pLabels = {groupFactorName};
        statsResults.Table = {};
        statsResults.PostHoc = table();
        statsResults.EffectSize = struct();
        return;
    end

    % ---------- Main test ----------
    % Before even attempting a two-way ANOVA, check whether Group and
    % Treatment are actually crossed (each Group has >1 Treatment level
    % represented, and vice versa). If they're not - e.g. Treatment is
    % really just a one-off label attached to a single Group each time -
    % anovan's interaction (and often main-effect) terms are
    % mathematically inestimable and it silently returns NaN p-values.
    % Catching this up front (rather than reporting NaN as if it were a
    % real result) and falling back to one-way ANOVA on Group is the
    % scientifically honest thing to do.
    attemptTwoWay = strcmpi(anovaMode, 'twoway') && hasTreatment;
    if attemptTwoWay
        combos = unique(resultsTable(:, {'Group', treatmentVar}), 'rows');
        comboLabelsForSort = strings(height(combos), 1);
        for ci = 1:height(combos)
            comboLabelsForSort(ci) = curveComboLabel(combos.Group(ci), combos.(treatmentVar)(ci));
        end
        [~, sortOrder] = ismember(sortByConcentration(comboLabelsForSort), comboLabelsForSort);
        combos = combos(sortOrder, :);
        [~, ~, groupIdx] = unique(combos.Group);
        treatmentsPerGroup = accumarray(groupIdx, 1);
        if all(treatmentsPerGroup <= 1)
            attemptTwoWay = false;
            statsResults.Warning = ['Requested two-way ANOVA, but Group and Treatment are not ' ...
                'crossed (every Group has only one Treatment value) - the interaction term cannot ' ...
                'be estimated from this design. Falling back to one-way ANOVA on Group only. ' ...
                'Treat the Treatment column as exploratory/uncontrolled for this dataset, not a ' ...
                'tested factor.'];
        end
    end

    if isNormal
        if attemptTwoWay
            [p, tbl, anovaStats] = anovan(resultsTable.PeakForce_N, ...
                {resultsTable.Group, resultsTable.(treatmentVar)}, ...
                'model', 'interaction', ...
                'sstype', 3, ...
                'varnames', {'Group', 'Treatment'}, ...
                'display', 'off');

            if any(isnan(p))
                % anovan itself hit a rank-deficient/inestimable term even
                % though the pre-check above passed (e.g. thin but
                % technically-crossed cells) - same fallback, reported
                % honestly rather than shown as a result.
                statsResults.Warning = ['Two-way ANOVA could not be estimated (returned NaN p-values), ' ...
                    'most likely because too few Group/Treatment combinations are replicated to separate ' ...
                    'the interaction (and possibly main effects) from noise. Falling back to one-way ANOVA ' ...
                    'on Group only.'];
                attemptTwoWay = false;
            else
                statsResults.Test = 'Two-way ANOVA (Type III SS)';
                statsResults.p = p;
                statsResults.pLabels = {'Group', 'Treatment', 'Interaction'};
                statsResults.Table = tbl;

                % Effect sizes: partial eta-squared per term = SS_term / (SS_term + SS_error)
                % tbl is anovan's ANOVA table cell array: row 1 = headers,
                % rows 2:4 = Group/Treatment/Interaction, row 5 = Error, row 6 = Total.
                % tbl{row,2} already returns the numeric SS value directly (no extra
                % cell dereference needed).
                errorRowIdx = find(strcmp(tbl(:,1), 'Error'), 1);
                ssError = tbl{errorRowIdx, 2};
                statsResults.EffectSize = struct();
                for termIdx = 1:3
                    ssTerm = tbl{1 + termIdx, 2};
                    statsResults.EffectSize.(matlab.lang.makeValidName(statsResults.pLabels{termIdx})) = ...
                        ssTerm / (ssTerm + ssError);
                end

                % Post-hoc pairwise comparisons, one set per factor.
                % Level names/order are pulled directly from anovaStats.grpnames
                % (not re-derived independently) so they can never be
                % mismatched against what multcompare's row indices refer to.
                c1 = multcompare(anovaStats, 'Dimension', 1, 'Display', 'off');
                c2 = multcompare(anovaStats, 'Dimension', 2, 'Display', 'off');
                groupLevels = anovaStats.grpnames{1};
                treatLevels = anovaStats.grpnames{2};
                postHoc1 = formatPostHoc(c1, groupLevels, 'Group');
                postHoc2 = formatPostHoc(c2, treatLevels, 'Treatment');
                statsResults.PostHoc = [postHoc1; postHoc2];
                statsResults.PostHocMethod = 'Tukey-Kramer HSD (per factor)';
            end
        end

        if ~attemptTwoWay
            [p, tbl, anovaStats] = anova1(resultsTable.PeakForce_N, effectiveGroupCol, 'off');
            statsResults.Test = 'One-way ANOVA';
            statsResults.p = p;
            statsResults.pLabels = {groupFactorName};
            statsResults.Table = tbl;

            ssBetween = tbl{2, 2};
            ssTotal = tbl{4, 2};
            statsResults.EffectSize.EtaSquared = ssBetween / ssTotal;

            c = multcompare(anovaStats, 'Display', 'off');
            statsResults.PostHoc = formatPostHoc(c, anovaStats.gnames, groupFactorName);
            statsResults.PostHocMethod = 'Tukey-Kramer HSD';
        end
    else
        [p, tbl, kwStats] = kruskalwallis(resultsTable.PeakForce_N, effectiveGroupCol, 'off');
        statsResults.Test = 'Kruskal-Wallis';
        statsResults.p = p;
        statsResults.pLabels = {groupFactorName};
        statsResults.Table = tbl;

        % Epsilon-squared effect size for Kruskal-Wallis: (H - k + 1) / (n - k)
        H = tbl{2, 5};
        k = nG;
        n = height(resultsTable);
        statsResults.EffectSize.EpsilonSquared = (H - k + 1) / (n - k);

        c = multcompare(kwStats, 'CriticalValueType', 'dunn-sidak', 'Display', 'off');
        statsResults.PostHoc = formatPostHoc(c, kwStats.gnames, groupFactorName);
        statsResults.PostHocMethod = 'Dunn-Sidak (rank-based, pairwise)';
    end
end

function [normRows, isNormal] = appendNormalityRow(normRows, isNormal, groupVal, treatmentVal, vals, minN)
    n = numel(vals);
    if n >= minN
        [W, p] = shapiroWilkTest(vals);
        if p < 0.05
            result = 'Non-normal';
            isNormal = false;
        else
            result = 'Normal';
        end
    else
        W = NaN;
        p = NaN;
        result = sprintf('Not tested (n<%d)', minN);
    end
    normRows(end+1, :) = {groupVal, treatmentVal, n, W, p, string(result)}; %#ok<AGROW>
end

function postHocTable = formatPostHoc(c, levels, factorName)
    % c columns from multcompare: [group1Idx, group2Idx, lowerCI, meanDiff, upperCI, pValue]
    nRows = size(c, 1);
    factorCol = repmat(string(factorName), nRows, 1);
    g1 = strings(nRows, 1);
    g2 = strings(nRows, 1);
    for i = 1:nRows
        g1(i) = string(levels(c(i, 1)));
        g2(i) = string(levels(c(i, 2)));
    end
    postHocTable = table(factorCol, g1, g2, c(:,4), c(:,3), c(:,5), c(:,6), ...
        'VariableNames', {'Factor', 'Group1', 'Group2', 'MeanDiff', 'CI_Lower', 'CI_Upper', 'pValue'});
end
