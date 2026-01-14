% sim_channel_sounding.m
% 任务一仿真：离线模拟“全1导频”宽带信道探测
% 目的：验证基于全1导频（频域全1，时域脉冲）的信道估计、PDP绘制及RMS时延扩展计算逻辑。

clc; clear; close all;

%% 1. 参数设置 (System Parameters)
fs = 7.68e6;            % 采样率: 7.68 MHz
nFFT = 512;             % FFT大小 (对应子载波间隔 15kHz)
cpLen = 36;             % 循环前缀长度 (约 4.7us)
numSymbols = 10;        % 模拟发送的符号数

disp(['--- Channel Sounding Simulation ---']);
disp(['Sample Rate: ', num2str(fs/1e6), ' MHz']);
disp(['Tone Spacing: ', num2str(fs/nFFT/1e3), ' kHz']);

%% 2. 信号生成 (Signal Generation - All 1s Pilot)
% 频域全1导频 (All-1s in Frequency Domain)
% 注意：这在时域会导致极高的PAPR (脉冲)，但能最直接地探测信道冲击响应
TxPilotFreq = ones(nFFT, 1); 

% OFDM调制 (IFFT + CP)
TxPilotTime = ifft(TxPilotFreq, nFFT) * sqrt(nFFT); % 归一化能量
TxBlock = [TxPilotTime(end-cpLen+1:end); TxPilotTime]; % 添加CP

% 构建发送帧 (重复发送以提高信噪比)
TxFrame = repmat(TxBlock, numSymbols, 1);

disp('Signal Generated: Frequency Domain All-1s (Time Domain Pulse)');

%% 3. 信道模拟 (Simulated Multipath Channel)
% 模拟一个典型的室内多径信道
% 路径1: LOS, 0us, 0dB
% 路径2: 反射, 0.3us (约2.3个样点), -6dB
% 路径3: 远反, 1.2us (约9.2个样点), -15dB
ts = 1/fs;
tau_profile = [0, 3e-7, 1.2e-6]; 
pdb_profile = [0, -6, -15]; % dB
path_gains = 10.^(pdb_profile./20);

% 将连续时延映射到离散抽头
channel_taps = zeros(20, 1);
for i = 1:length(tau_profile)
    idx = round(tau_profile(i)/ts) + 1;
    channel_taps(idx) = path_gains(i);
end

disp('Simulating Multipath Channel...');
% 通过信道
RxSignalRaw = filter(channel_taps, 1, TxFrame);

% 添加高斯白噪声 (SNR = 20dB)
RxSignal = awgn(RxSignalRaw, 20, 'measured');

%% 4. 接收与信道估计 (Receiver & Estimation)
% 假设实现了完美的符号同步 (直接重塑矩阵)
RxMatrix = reshape(RxSignal, nFFT + cpLen, numSymbols);
RxPayload = RxMatrix(cpLen+1:end, :); % 去除CP

% FFT 变换到频域
RxFreq = fft(RxPayload, nFFT) / sqrt(nFFT);

% LS信道估计 (H_est = Y / X)
% 因为 X (发送导频) 全为1，所以 H_est = Y
H_est_per_symbol = RxFreq ./ repmat(TxPilotFreq, 1, numSymbols);

% 对多个符号取平均以降噪
H_est = mean(H_est_per_symbol, 2);

%% 5. 数据分析 (Analysis)

% A. 功率延迟谱 (PDP - Power Delay Profile)
% PDP 是信道冲激响应(CIR)的模平方
h_time = ifft(H_est); % 变换回时域得到 CIR
pdp = abs(h_time).^2;
% 只取前一部分(CP长度内)，因为后面通常是噪声
pdp_cut = pdp(1:cpLen); 
time_axis_us = (0:length(pdp_cut)-1) * ts * 1e6;

% B. RMS 时延扩展 (RMS Delay Spread)
% 计算一阶矩 (平均时延)
pdp_linear = pdp_cut; % 线性功率
total_power = sum(pdp_linear);
tau_axis = (0:length(pdp_linear)-1).' * ts;

mean_delay = sum(pdp_linear .* tau_axis) / total_power;

% 计算二阶矩
second_moment = sum(pdp_linear .* (tau_axis.^2)) / total_power;

% RMS Delay Spread
rms_delay_spread = sqrt(second_moment - mean_delay^2);

% C. 频率相关函数 (FCF - Frequency Correlation Function)
% FCF 是 PDP 的傅里叶变换 (即信道频域响应的自相关)
% 或者直接计算频域响应的自相关
fcf = xcorr(H_est - mean(H_est), 'biased'); 
% 归一化
fcf = abs(fcf) / max(abs(fcf));
f_lags = (-(nFFT-1):(nFFT-1)) * (fs/nFFT/1e6); % MHz

%% 6. 绘图结果 (Plotting)
figure('Position', [100, 100, 1000, 600]);

% 1. 信道频域响应 (幅度)
subplot(2,2,1);
plot((0:nFFT-1)*(fs/nFFT/1e6), 20*log10(abs(H_est)));
title('Estimated Channel Frequency Response');
xlabel('Frequency (MHz)'); ylabel('Magnitude (dB)');
grid on;

% 2. 功率延迟谱 (PDP)
subplot(2,2,2);
stem(time_axis_us, 10*log10(pdp_cut), 'BaseValue', -60, 'MarkerFaceColor', 'b');
hold on;
xline(mean_delay*1e6, 'g--', 'Mean Delay');
xline((mean_delay+rms_delay_spread)*1e6, 'r--', 'RMS Spread');
title(['PDP (RMS Delay: ' num2str(rms_delay_spread*1e6, '%.2f') ' us)']);
xlabel('Delay (\mus)'); ylabel('Power (dB)');
legend('PDP', 'Mean Delay', 'RMS Boundary');
grid on;
ylim([-50 5]);

% 3. 频率相关函数 (FCF)
subplot(2,2,3);
plot(f_lags, fcf);
title('Frequency Correlation Function (FCF)');
xlabel('Frequency Lag (MHz)'); ylabel('Correlation');
xlim([-2 2]); % 关注中心区域
grid on;

% 4. 原始发送 vs 接收 (时域一个符号)
subplot(2,2,4);
plot(abs(TxBlock), 'b'); hold on;
plot(abs(RxMatrix(:,1)), 'r--');
title('Time Domain Signal (One Symbol)');
legend('Tx (Pulse)', 'Rx (Multipath)');
xlabel('Samples'); ylabel('Amplitude');
grid on;

saveas(gcf, 'sim_channel_sounding_results.png');
disp('Simulation Complete. Results saved to sim_channel_sounding_results.png');
