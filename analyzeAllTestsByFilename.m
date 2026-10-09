function [resultsTable, curves, log] = analyzeAllTestsByFilename(rootFolder, tieRule)
%ANALYZEALLTESTSBYFILENAME Batch-process every pull-out test data file
%   found anywhere under rootFolder (searched recursively - any
%   subfolder depth is fine), using the filename itself to identify
%   TestID, concentration group, and a treatment/modifier tag - e.g.
%   T1-10mM-noPT-tensile_test_20260625_180234.csv or the messier
%   T4_20mM_SuperGlue_tensile_test_20260716_171040.csv - see
%   parseTestFilename.m for exactly what's tolerated.
%
%   Accepted data formats: .csv, .tsv, .xlsx, .xls (any mix in the same
%   folder is fine - each file is read according to its own extension).
%
%   A file with a missing TestID or concentration is still included
%   (with a fallback ID / Group='Unknown') and flagged in the log with a
%   NOTE line - it is not silently dropped. Only files missing the
%   tensile_test_DATE_TIME suffix entirely, or with unreadable data
%   columns, are skipped (logged with a SKIPPED line).
%
%   Returns:
%     resultsTable - TestID, Group (=concentration), Treatment
%                    (PT/noPT if that's what the filename encodes,
%                    otherwise the raw modifier text, or 'none'),
%                    PeakForce_N, DispAtPeak_mm
%     curves       - struct array with TestID, Group, Treatment,
%                    Displacement, Load (full curves, for overlay plots)
%     log          - cell array of NOTE (metadata inferred) and SKIPPED
%                    (file excluded) messages

    resultsTable = table('Size', [0 5], ...
        'VariableTypes', {'string', 'string', 'string', 'double', 'double'}, ...
        'VariableNames', {'TestID', 'Group', 'Treatment', 'PeakForce_N', 'DispAtPeak_mm'});

    curves = struct('TestID', {}, 'Group', {}, 'Treatment', {}, 'Displacement', {}, 'Load', {});
    log = {};

    % Supported formats: CSV, TSV, Excel (xlsx/xls)
    extensions = {'*.csv', '*.tsv', '*.xlsx', '*.xls'};
    dataFiles = [];
    for e = 1:numel(extensions)
        dataFiles = [dataFiles; dir(fullfile(rootFolder, '**', extensions{e}))]; %#ok<AGROW>
    end

    for i = 1:numel(dataFiles)
        dataPath = fullfile(dataFiles(i).folder, dataFiles(i).name);
        try
            meta = parseTestFilename(dataFiles(i).name);

            % Metadata that couldn't be determined (missing TestID or
            % concentration) does NOT skip the file - it's included with
            % a fallback/Unknown value and flagged here so it's visible
            % and fixable, rather than the test's data silently vanishing.
            for w = 1:numel(meta.Warnings)
                log{end+1} = sprintf('NOTE %s: %s', dataFiles(i).name, meta.Warnings{w}); %#ok<AGROW>
            end

            T = loadPulloutData(dataPath);
            [peakForce, dispAtPeak] = getPeakForce(T.Displacement, T.Load, tieRule);

            resultsTable(end+1, :) = {meta.TestID, meta.GroupValue, meta.Treatment, ...
                peakForce, dispAtPeak}; %#ok<AGROW>

            curves(end+1) = struct( ...
                'TestID', meta.TestID, ...
                'Group', meta.GroupValue, ...
                'Treatment', meta.Treatment, ...
                'Displacement', T.Displacement, ...
                'Load', T.Load); %#ok<AGROW>
        catch ME
            % Only a genuinely unreadable file (bad data columns, or a
            % filename missing the tensile_test_DATE_TIME suffix
            % entirely) actually gets skipped.
            log{end+1} = sprintf('SKIPPED %s: %s', dataPath, ME.message); %#ok<AGROW>
        end
    end
end
