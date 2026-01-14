% probe_channel_fixed.m - Single USRP Loopback using Separate Objects
% Attempting to use separate TX and RX objects for N210

clc; clear; close all;
rng(42);

%% 1. Parameters
USRP_IP = '192.168.10.2';
FC = 1.9e9; % Center Freq
GainTX = 10;
GainRX = 10;
Interp = 20; % TX Rate = 100e6/20 = 5e6
Decim = 20;  % RX Rate = 100e6/20 = 5e6 (Matched)

%% 2. Load Signal
if ~isfile('TransmitSignal.mat')
    error('TransmitSignal.mat missing.');
end
tmp = load('TransmitSignal.mat');
% Extract signal robustly
vars = fieldnames(tmp);
txSigRaw = tmp.(vars{1});

% Add ZC for Sync
zcLength = 503;
zcSequence = zadoffChuSeq(25, zcLength);
txSig = [zcSequence; txSigRaw; zeros(2000,1)]; 

%% 3. Setup Objects
disp('Creating TX Object...');
tx = comm.SDRuTransmitter(...
    'Platform', 'N200/N210/USRP2', ...
    'IPAddress', USRP_IP, ...
    'CenterFrequency', FC, ...
    'Gain', GainTX, ...
    'InterpolationFactor', Interp);
    
disp('Creating RX Object...');
rx = comm.SDRuReceiver(...
    'Platform', 'N200/N210/USRP2', ...
    'IPAddress', USRP_IP, ...
    'CenterFrequency', FC, ...
    'Gain', GainRX, ...
    'DecimationFactor', Decim, ...
    'SamplesPerFrame', length(txSig), ...
    'OutputDataType', 'double');

% Setup Burst Mode / Overrun
tx.UnderrunOutputPort = true;
rx.OverrunOutputPort = true;

%% 4. Transmission/Reception Loop
disp('Starting Transmission...');

% We will attempt to transmit repeatedly in a loop while receiving
% This is "Pseudo-Loopback". On some setups, step(rx) blocks TX.
% We'll try to interleave.

capturedData = [];
maxIter = 20;

try
    for i = 1:maxIter
        % TX
        tx(txSig);
        
        % RX
        [d, len, over] = rx();
        
        if len > 0
            capturedData = [capturedData; d];
        end
        
        if mod(i, 5) == 0
            fprintf('Loop %d/%d, Captured: %d samples\n', i, maxIter, length(capturedData));
        end
    end
catch ME
    disp('Error during loopback:');
    disp(ME.message);
    disp('Releasing resources...');
    release(tx);
    release(rx);
    rethrow(ME);
end

release(tx);
release(rx);

%% 5. Sync and Save
if isempty(capturedData)
    warning('No data captured!');
else
    disp('Data captured. Syncing...');
    
    % Correlation
    [corrVals, lags] = xcorr(capturedData, zcSequence);
    [maxVal, maxIdx] = max(abs(corrVals));
    
    disp(['Max Correlation: ', num2str(maxVal)]);
    
    % Plot
    f = figure('visible', 'off');
    plot(abs(corrVals));
    title(['Sync Peak: ', num2str(maxVal)]);
    saveas(f, 'probe_sync_result.png');
    
    % Save
    RXusrp_data = capturedData;
    save('RXusrp_data.mat', 'RXusrp_data', '-v7.3');
    disp('Saved RXusrp_data.mat');
end
