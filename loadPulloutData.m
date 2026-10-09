function T = loadPulloutData(filePath)
%LOADPULLOUTDATA Load a single pull-out test file (CSV, TSV, or Excel)
%   and return a 2-column table with variables Displacement and Load.
%
%   Supported formats: .csv, .tsv, .xlsx, .xls
%
%   Column detection: matches header text containing "displac" for
%   displacement and "load" or "force" for load, case-insensitively, so
%   exact header wording/units (e.g. "Displacement (mm)") doesn't matter.
%   Falls back to fixed column positions (3 = displacement, 4 = load) if
%   no matching headers are found, to tolerate raw/headerless exports.

    [~, ~, ext] = fileparts(filePath);
    ext = lower(ext);

    switch ext
        case '.csv'
            raw = readtable(filePath, 'FileType', 'text', ...
                'Delimiter', ',', 'VariableNamingRule', 'preserve');
        case '.tsv'
            raw = readtable(filePath, 'FileType', 'text', ...
                'Delimiter', '\t', 'VariableNamingRule', 'preserve');
        case {'.xlsx', '.xls'}
            raw = readtable(filePath, 'FileType', 'spreadsheet', ...
                'VariableNamingRule', 'preserve');
        otherwise
            error('loadPulloutData:unsupportedFormat', ...
                'Unsupported file type "%s" (supported: .csv, .tsv, .xlsx, .xls): %s', ...
                ext, filePath);
    end

    varNames = lower(string(raw.Properties.VariableNames));

    dispCol = find(contains(varNames, "displac"), 1);
    loadCol = find(contains(varNames, "load") | contains(varNames, "force"), 1);

    if isempty(dispCol) || isempty(loadCol)
        if width(raw) >= 4
            dispCol = 3;
            loadCol = 4;
        else
            error('loadPulloutData:columnsNotFound', ...
                'Could not identify Displacement/Load columns in %s', filePath);
        end
    end

    displacement = raw{:, dispCol};
    load = raw{:, loadCol};

    % Drop non-numeric / NaN rows (blank trailing rows, footer text, etc.)
    valid = isfinite(displacement) & isfinite(load);

    T = table(displacement(valid), load(valid), ...
        'VariableNames', {'Displacement', 'Load'});
end
