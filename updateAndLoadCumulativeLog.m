function cumulativeTable = updateAndLoadCumulativeLog(resultsTable, logPath)
%UPDATEANDLOADCUMULATIVELOG Append this run's results to a persistent
%   log file and return the full accumulated history across all runs
%   that have ever been logged to this file.
%
%   cumulativeTable = UPDATEANDLOADCUMULATIVELOG(resultsTable, logPath)
%
%   resultsTable - current run's table (TestID, Group, Treatment,
%                  PeakForce_N, DispAtPeak_mm)
%   logPath      - path to a CSV file that persists across MATLAB
%                  sessions/runs; created if it doesn't exist yet
%
%   Each row gets a RunID (timestamp) and RunDate tag. Rows that are an
%   exact content duplicate of an already-logged row (same TestID,
%   Group, Treatment, PeakForce_N, DispAtPeak_mm) are not re-added, so
%   clicking "Generate PPTX Report" more than once for the same analysis
%   run doesn't inflate the cumulative history - but re-analyzing the
%   same folder later (e.g. after adding more test files) will correctly
%   add only the genuinely new rows.

    runID = string(datestr(now, 'yyyymmdd_HHMMSS')); %#ok<TNOW1,DATST>
    runDate = string(datestr(now, 'yyyy-mm-dd')); %#ok<TNOW1,DATST>

    newRows = resultsTable(:, {'TestID', 'Group', 'Treatment', 'PeakForce_N', 'DispAtPeak_mm'});
    newRows.RunID = repmat(runID, height(newRows), 1);
    newRows.RunDate = repmat(runDate, height(newRows), 1);

    if isfile(logPath)
        existing = readtable(logPath, 'VariableNamingRule', 'preserve');
        % Coerce types back to what they were before the CSV round-trip
        % (readtable's text-type inference isn't guaranteed to match
        % what was originally written), so concatenation below is safe.
        existing.TestID = string(existing.TestID);
        existing.Group = string(existing.Group);
        existing.Treatment = string(existing.Treatment);
        existing.PeakForce_N = double(existing.PeakForce_N);
        existing.DispAtPeak_mm = double(existing.DispAtPeak_mm);
        existing.RunID = string(existing.RunID);
        existing.RunDate = string(existing.RunDate);

        keyOf = @(t) strcat(t.TestID, "|", t.Group, "|", t.Treatment, "|", ...
            string(t.PeakForce_N), "|", string(t.DispAtPeak_mm));
        isDuplicate = ismember(keyOf(newRows), keyOf(existing));
        newRows = newRows(~isDuplicate, :);

        cumulativeTable = [existing; newRows];
    else
        cumulativeTable = newRows;
    end

    writetable(cumulativeTable, logPath);
end
