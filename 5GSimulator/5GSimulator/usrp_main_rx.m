function rxSummary = usrp_main_rx(captureFile, configName)
%USRP_MAIN_RX Post-process a captured USRP waveform with sync/decoding.
%   The function reuses sdr_experiment_main in "rx-process" mode. It
%   expects the capture MAT file to contain one of:
%     - rxCapture
%     - rx_signal
%     - rxSignal
%
%   Inputs:
%     captureFile (string) : MAT file with captured complex samples
%     configName  (string) : experiment config name used on transmitter
%
%   Outputs:
%     rxSummary (struct) : KPIs, parameter snapshots, and sync settings
%
%   Example:
%     % 基于 tx_waveform_baseline10Mbps 发送的回环捕获解码
%     usrp_main_rx("capture.mat", "baseline10Mbps");

if nargin < 1 || isempty(captureFile)
    captureFile = "capture.mat";
end
if nargin < 2 || isempty(configName)
    configName = "baseline10Mbps";
end

rxSummary = sdr_experiment_main("rx-process", configName, ...
    'CaptureFile', captureFile, ...
    'SaveWaveform', false);

if ~isempty(rxSummary.kpi.meanThroughput)
    fprintf('Decoded capture from %s; mean throughput %.2f (units per simulator definition)\n', ...
        captureFile, rxSummary.kpi.meanThroughput);
else
    fprintf('Capture from %s processed without KPI extraction (rx-processing disabled or missing results).\n', ...
        captureFile);
end
end
