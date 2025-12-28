function txMetadata = usrp_main_tx(configName, outputDir)
%USRP_MAIN_TX Prepare baseband with sync head for on-air transmission.
%   The function delegates to sdr_experiment_main in "tx-only" mode to
%   generate the baseband waveform, parameter snapshot, and sync settings.
%
%   Inputs:
%     configName (string) : experiment config, e.g., "baseline10Mbps"
%     outputDir  (string) : folder to store tx_waveform_<config>.mat
%
%   Outputs:
%     txMetadata (struct) : summary of the generated waveform and params
%
%   Example:
%     % 生成 10 MHz、16QAM 基线的 USRP 发送波形
%     usrp_main_tx("baseline10Mbps", "results");

if nargin < 1 || isempty(configName)
    configName = "baseline10Mbps";
end
if nargin < 2 || isempty(outputDir)
    outputDir = "results";
end

txMetadata = sdr_experiment_main("tx-only", configName, ...
    'OutputDir', outputDir, ...
    'SaveWaveform', true);

fprintf('USRP tx waveform for "%s" saved to %s/tx_waveform_%s.mat\n', ...
    configName, outputDir, configName);
end
