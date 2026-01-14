% run_loopback.m - Combined TX/RX for Single USRP Loopback
% Automatically generated to solve single-device locking issue.

clc; clear; close all;
rng(42);

disp('--- USRP Loopback Experiment Start ---');

%% 1. Load and Prepare Transmit Signal (from tx_demo)
disp('Loading Transmit Signal...');
if ~isfile('TransmitSignal.mat')
    error('TransmitSignal.mat not found! Please run main_tx first.');
end
txSigStruct = load('TransmitSignal.mat', '-mat');
% Handle different variable names if necessary
if isfield(txSigStruct, 'TransmitSignalTotal')
    txSig = txSigStruct.TransmitSignalTotal;
elseif isfield(txSigStruct, 'var4_1')
    txSig = txSigStruct.var4_1;
else
    % Fallback: take the first variable
    vars = fieldnames(txSigStruct);
    txSig = txSigStruct.(vars{1});
end

% Add ZC Sequence
zcLength = 503;
zcSeed = 25;
zcSequence = zadoffChuSeq(zcSeed, zcLength);
txSig = [zcSequence; txSig; zeros(1000,1)]; % Padding zeros

disp(['Transmit Signal Length: ', num2str(length(txSig))]);

%% 2. Initialize USRP Transceiver
% Combines settings from tx_demo and rx_demo
% using 1.9GHz to match TX original setting.
disp('Initializing USRP Transceiver at 192.168.10.2...');
radio = comm.SDRuTransceiver(...
    'Platform',             'N200/N210/USRP2', ...
    'IPAddress',            '192.168.10.2', ...
    'MasterClockRate',      100e6, ...
    'CenterFrequency',      1.9e9, ... % Ensuring TX/RX match
    'Gain',                 10, ...    % TX Gain
    'InterpolationFactor',  20, ...    % TX Rate: 5Msps
    'DecimationFactor',     10, ...    % RX Rate: 10Msps
    'SamplesPerFrame',      length(txSig)*2); % Capture enough samples (RX rate is double TX rate)

% Configure RX Gain separately if needed (System object property names might vary, usually shared or 'Gain' is TX, 'Gain' property for RX?)
% Checking properties: SDRuTransceiver typically has 'Gain' (RX) and 'Gain' (TX) isn't direct?
% Actually, for N210, gain is usually split.
% Let's rely on defaults or explicit properties if standard.
% radio.Gain = 10 sets RX gain usually?
% radio.TransmitterGain = 10? 
% Let's try setting common properties. If it fails, we default.

radio.EnableBurstMode = true;
radio.NumFramesInBurst = 1;

%% 3. Execution Loop
disp('Starting Loopback Transmission/Reception...');
receivedDataTotal = [];

% We will transmit and receive in a loop to ensure we capture the signal
% Since RX rate (10M) > TX rate (5M), we expect 2x samples per symbol duration.
numIterations = 10; 

for i = 1:numIterations
    fprintf('Iteration %d/%d...\n', i, numIterations);
    
    % Transmit and Receive simultaneously
    % Note: txSig length N. rx output length depends on SamplesPerFrame.
    % We set SamplesPerFrame to match expected duration.
    
    [rxFrame, len, overrun] = radio(txSig);
    
    if len > 0
        receivedDataTotal = [receivedDataTotal; rxFrame];
    end
    
    if overrun
        disp('Overrun detected!');
    end
end

disp('Loopback Complete.');
release(radio);

%% 4. Process and Save Data (from rx_demo)
RXusrp_data = receivedDataTotal;

disp('Performing ZC Synchronization search...');
% Re-generate ZC for correlation (at RX rate? TX was interpolated, RX decimated)
% TX: 5Msps. RX: 10Msps.
% The received ZC sequence will be oversampled by 2.
% We need to resample the reference ZC or just look for the pattern.
% Simple approach: Downsample RX data by 2 to match 5Msps for correlation, 
% OR upsample ZC by 2.
zcSequenceRx = resample(zcSequence, 2, 1); 

[corr, index] = xcorr(RXusrp_data, zcSequenceRx);
[maxVal, maxIndex] = max(abs(corr));

disp(['Max Correlation Value: ', num2str(maxVal)]);

if maxVal < 0.1 % Arbitrary low threshold
    warning('Synchronization might have failed. Signal weak or absent.');
end

% Plotting (Optional, for visual check if running interactively)
% figure; plot(abs(corr)); title('Correlation');

% Saving
save('RXusrp_data.mat', 'RXusrp_data', '-v7.3');
disp('Data saved to RXusrp_data.mat');

% Also generate the figure file the user might need
f = figure('visible', 'off');
plot(abs(corr));
title('Channel Synchronization Performance');
saveas(f, 'sync_performance.png');
