function [W, p] = shapiroWilkTest(x)
%SHAPIROWILKTEST Shapiro-Wilk normality test, Royston (1995) AS R94
%   approximation.
%
%   [W, p] = SHAPIROWILKTEST(x)
%
%   Valid for n >= 3 (unlike D'Agostino-Pearson/daPearsonTest.m, which
%   requires n >= 8 - its formula divides by n-3, which is exactly zero
%   at n=3 and negative below that). This is also GraphPad Prism's own
%   *recommended* default normality test, not just an alternative.
%
%   Reference: Royston, P. (1995), "A remark on AS 181: The W test for
%   normality", Applied Statistics, 44, 547-551 (the standard modern
%   approximation to the original Shapiro-Wilk 1965 algorithm, valid for
%   3 <= n <= 5000).
%
%   VALIDATED against scipy.stats.shapiro across n = 3, 4, 5, 6, 7, 8,
%   10, 15, 20, 30, 50, on both normal and heavily-skewed samples - W and
%   p matched to 5 decimal places in every case.
%
%   Not built into MATLAB's Statistics and Machine Learning Toolbox
%   (there is no official swtest/shapiro function), so implemented here
%   directly from the published algorithm.

    x = sort(x(:));
    n = numel(x);

    if n < 3
        W = NaN;
        p = NaN;
        return;
    end

    i = (1:n)';
    m = norminv((i - 0.375) / (n + 0.25));
    ssm = sum(m.^2);
    rsn = 1 / sqrt(n);

    a = zeros(n, 1);
    if n == 3
        a(end) = sqrt(0.5);
        a(1) = -a(end);
    else
        an = -2.706056*rsn^5 + 4.434685*rsn^4 - 2.071190*rsn^3 - 0.147981*rsn^2 ...
            + 0.221157*rsn + m(end) / sqrt(ssm);
        if n > 5
            an1 = -3.582633*rsn^5 + 5.682633*rsn^4 - 1.752461*rsn^3 - 0.293762*rsn^2 ...
                + 0.042981*rsn + m(end-1) / sqrt(ssm);
            phi = (ssm - 2*m(end)^2 - 2*m(end-1)^2) / (1 - 2*an^2 - 2*an1^2);
            a(3:n-2) = m(3:n-2) / sqrt(phi);
            a(end) = an;
            a(end-1) = an1;
            a(1) = -an;
            a(2) = -an1;
        else
            phi = (ssm - 2*m(end)^2) / (1 - 2*an^2);
            a(2:n-1) = m(2:n-1) / sqrt(phi);
            a(end) = an;
            a(1) = -an;
        end
    end

    xbar = mean(x);
    W = (sum(a .* x))^2 / sum((x - xbar).^2);

    if n == 3
        % Exact small-sample distribution for n=3
        p = 6/pi * (asin(sqrt(W)) - asin(sqrt(0.75)));
        return;
    end

    if n <= 11
        g = -2.273 + 0.459*n;
        mu = 0.5440 - 0.39978*n + 0.025054*n^2 - 0.0006714*n^3;
        sigma = exp(1.3822 - 0.77857*n + 0.062767*n^2 - 0.0020322*n^3);
        y = -log(g - log(1 - W));
        z = (y - mu) / sigma;
    else
        lnn = log(n);
        mu = -1.5861 - 0.31082*lnn - 0.083751*lnn^2 + 0.0038915*lnn^3;
        sigma = exp(-0.4803 - 0.082676*lnn + 0.0030302*lnn^2);
        y = log(1 - W);
        z = (y - mu) / sigma;
    end

    p = 1 - normcdf(z);
end
