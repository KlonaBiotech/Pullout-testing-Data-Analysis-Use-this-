function meta = parseTestFilename(filename)
%PARSETESTFILENAME Extract test metadata from a pull-out test filename.
%
%   Handles two different experimental designs, auto-detected per file:
%
%   1. Concentration sweep (Group = crosslinker concentration):
%       T1-10mM-noPT-tensile_test_20260625_180234.csv
%       T0_1mMGenipin_tensile_test_20260716_161353.csv
%       T4_20mM_SuperGlue_tensile_test_20260716_171040.csv
%       T7_5mM_trial1_tensile_test_20260716_174532.csv
%
%   2. Fiber-type comparison at fixed concentration (Group = fiber type),
%      used whenever no "<number>mM" pattern is found in the filename:
%       T1_PDO_tensile_test_20260724_113312.csv        -> Group='PDO'
%       T2_PGAMulti_trial2_tensile_test_...csv          -> Group='PGAMulti', Treatment='trial2'
%       25_PLLATwist_tensile_test_20260727_1534...csv   -> no 'T' prefix, still handled
%       T8_PGAMulti_tensile_test_20260724.csv           -> date only, no time, still handled
%
%   Also handles: TestID absent entirely, "T" prefix absent (bare
%   number), concentration/fiber-type glued directly onto a modifier word
%   with no separator (e.g. "1mMGenipin"), separators that are dashes,
%   underscores, or missing, and a trailing timestamp that is date-only
%   or date_time.
%
%   The only hard requirement is a trailing "tensile_test_DATE[_TIME]"
%   suffix - everything before it is parsed on a best-effort basis, and
%   pieces that can't be determined are flagged in meta.Warnings rather
%   than causing an error, so a file with incomplete metadata is still
%   included in the analysis (visible and flagged) instead of silently
%   dropped.
%
%   Returns a struct:
%     TestID     - e.g. 'T1', normalized to include the 'T' even if the
%                  filename didn't have one, or a fallback derived from
%                  the timestamp if no number was found at all
%     GroupValue - the grouping variable for this experiment: a
%                  normalized '<number>mM' concentration if one was
%                  found, otherwise the leading fiber-type-like token
%                  (e.g. 'PDO', 'PGAMulti'), otherwise 'Unknown'
%     Treatment  - remaining modifier text after Group is removed (e.g.
%                  'Genipin', 'SuperGlue', 'trial1', 'trial2'),
%                  normalized to 'PT'/'noPT' if that's literally what it
%                  says, 'none' if there was no modifier
%     DateStr, TimeStr - as found in the filename (TimeStr is '' if the
%                  filename only had a date)
%     Warnings   - cell array of strings describing anything that had to
%                  be inferred or defaulted (empty if the filename
%                  matched the full expected convention)

    [~, name, ~] = fileparts(filename);
    warnings = {};

    % Only hard requirement: a trailing tensile_test_DATE[_TIME] suffix.
    % (Found via match start position, not a leading capture group, since
    % a capture group that can match zero-length text is handled
    % inconsistently across regex engines.)
    [suffixStart, suffixTokens] = regexp(name, 'tensile_test_(\d{8})(?:_(\d{6}))?$', ...
        'start', 'tokens', 'once');
    if isempty(suffixTokens)
        error('parseTestFilename:noMatch', ...
            'Filename is missing the expected "..._tensile_test_DATE[_TIME]" suffix: %s', filename);
    end

    prefix = name(1 : suffixStart - 1);
    dateStr = suffixTokens{1};
    if numel(suffixTokens) >= 2 && ~isempty(suffixTokens{2})
        timeStr = suffixTokens{2};
    else
        timeStr = '';
    end
    prefix = regexprep(prefix, '[-_]+$', ''); % drop trailing separator before "tensile_test"

    % --- TestID: optional "T" then digits, at the start of prefix ---
    testIdTokens = regexp(prefix, '^T?(\d+)[-_]?', 'tokens', 'once');
    if ~isempty(testIdTokens)
        testID = ['T' testIdTokens{1}];
        matchEnd = regexp(prefix, '^T?\d+[-_]?', 'end', 'once');
        rest = prefix(matchEnd + 1 : end);
    else
        fallbackTag = dateStr;
        if ~isempty(timeStr)
            fallbackTag = timeStr;
        end
        testID = sprintf('Unlabeled_%s', fallbackTag);
        rest = prefix;
        warnings{end+1} = sprintf('No test number found; assigned fallback ID %s.', testID); %#ok<AGROW>
    end

    % --- Group: try a concentration pattern first ("<number>mM", any
    %     case/spacing, possibly glued directly onto a modifier word) ---
    concTokens = regexp(rest, '^(\d+(?:\.\d+)?)\s*m[mM]', 'tokens', 'once');
    if ~isempty(concTokens)
        groupValue = [concTokens{1} 'mM'];
        matchEnd = regexp(rest, '^\d+(?:\.\d+)?\s*m[mM]', 'end', 'once');
        modifier = rest(matchEnd + 1 : end);
        modifier = regexprep(modifier, '^[-_]+', '');
    else
        % No concentration found - this experiment likely varies fiber
        % type instead (concentration held constant). Take the leading
        % letters+digits token as the group value, e.g. "PGAMulti" out of
        % "PGAMulti_trial2".
        fiberTokens = regexp(rest, '^([A-Za-z]+\d*)', 'tokens', 'once');
        if ~isempty(fiberTokens)
            groupValue = fiberTokens{1};
            matchEnd = regexp(rest, '^[A-Za-z]+\d*', 'end', 'once');
            modifier = rest(matchEnd + 1 : end);
            modifier = regexprep(modifier, '^[-_]+', '');
        else
            groupValue = 'Unknown';
            modifier = rest;
            warnings{end+1} = ['No concentration (e.g. "10mM") or fiber-type label found in ' ...
                'filename; assigned Group = Unknown.']; %#ok<AGROW>
        end
    end

    % --- Treatment/modifier normalization ---
    if isempty(modifier)
        treatment = 'none';
    elseif ~isempty(regexp(modifier, '^no[-_]?pt$', 'once', 'ignorecase'))
        treatment = 'noPT';
    elseif ~isempty(regexp(modifier, '^pt$', 'once', 'ignorecase'))
        treatment = 'PT';
    else
        treatment = modifier; % keep as-is: crosslinker name, reagent, trial label, etc.
    end

    meta.TestID = testID;
    meta.GroupValue = groupValue;
    meta.Treatment = treatment;
    meta.DateStr = dateStr;
    meta.TimeStr = timeStr;
    meta.Warnings = warnings;
end
