function [peakForce, dispAtPeak] = getPeakForce(displacement, load, tieRule)
%GETPEAKFORCE Find peak load and the displacement at which it occurs.
%
%   [peakForce, dispAtPeak] = GETPEAKFORCE(displacement, load, tieRule)
%
%   tieRule - 'first' or 'last'. If the max load value occurs at more
%   than one row (a plateau), 'first' takes the earliest occurrence,
%   'last' takes the latest (= higher displacement). This matches the
%   manual Excel convention: pick one rule and apply it consistently
%   across every test.

    if nargin < 3 || isempty(tieRule)
        tieRule = 'last';
    end

    [peakForce, ~] = max(load);
    tiedIdx = find(load == peakForce);

    switch lower(tieRule)
        case 'first'
            idx = tiedIdx(1);
        case 'last'
            idx = tiedIdx(end);
        otherwise
            error('getPeakForce:badTieRule', ...
                'tieRule must be ''first'' or ''last'', got ''%s''.', tieRule);
    end

    dispAtPeak = displacement(idx);
end
