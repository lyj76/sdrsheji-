% verify_channel_type.m
% Analyzes the captured RX data to determine channel characteristics
% (Cable vs. Wireless Lab Environment)

clc; clear; close all;

disp('--- Verifying Channel Data ---');

if ~isfile('RXusrp_data.mat')
    error('RXusrp_data.mat not found.');
end

load('RXusrp_data.mat'); % Loads 'RXusrp_data'
% Ensure data is column vector
if isrow(RXusrp_data), RXusrp_data = RXusrp_data.''; end

% Parameters
zcLength = 503;
zcRoot = 25;
zcSeq = zadoffChuSeq(zcRoot, zcLength);

% 1. Coarse Sync (Correlation)
disp('Calculating Cross-Correlation...');
[c, lags] = xcorr(RXusrp_data, zcSeq);
cAbs = abs(c);
[maxVal, maxIdx] = max(cAbs);

% 2. Extract Impulse Response Window (CIR)
% We look at a window around the peak
window = 100; 
idxStart = max(1, maxIdx - 20);
idxEnd = min(length(cAbs), maxIdx + window);
cir = cAbs(idxStart:idxEnd);
lags_window = lags(idxStart:idxEnd);

% 3. Calculate Stats
peakToAvg = maxVal / mean(cAbs);
noiseFloor = mean(cAbs(1:maxIdx-100)); % Estimate noise before peak
snr_est = 20*log10(maxVal / noiseFloor);

fprintf('Estimated SNR: %.2f dB\n', snr_est);

% 4. Plot
f = figure('visible', 'off');
subplot(2,1,1);
plot(lags, cAbs);
title(['Full Correlation (SNR \approx ' num2str(snr_est, '%.1f') ' dB)']);
xlabel('Lag'); ylabel('Magnitude');
grid on;

subplot(2,1,2);
plot(0:(length(cir)-1), cir, 'LineWidth', 1.5);
hold on;
yline(maxVal * 0.1, 'r--', '10% Threshold');
title('Channel Impulse Response (Detail)');
xlabel('Samples (Delay)'); ylabel('Magnitude');
legend('CIR', 'Multipath Threshold');
grid on;

saveas(f, 'channel_verification.png');
disp('Analysis complete. Check channel_verification.png');
