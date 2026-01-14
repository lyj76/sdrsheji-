% analyze_real_data_pdp.m
% 任务一实战：利用已有的 RXusrp_data.mat (线缆/近场数据) 进行信道分析
% 目的：对比“模拟的多径”与“实际的线缆信道”，验证是否为单径平坦信道。

clc; clear; close all;

disp('--- Analyzing Real USRP Data (PDP/FCF) ---');

%% 1. 加载实测数据
if ~isfile('RXusrp_data.mat')
    error('RXusrp_data.mat not found! Please run probe_channel_fixed.m first.');
end
load('RXusrp_data.mat'); % Load RXusrp_data
rx_signal = RXusrp_data;
if isrow(rx_signal), rx_signal = rx_signal.'; end

%% 2. 信号参数 (基于之前的 Zadoff-Chu 配置)
zcLength = 503;
zcRoot = 25;
ref_seq = zadoffChuSeq(zcRoot, zcLength);
fs = 10e6; % 假设接收采样率为 10Msps (Decimation=10 from 100M)
ts = 1/fs;

%% 3. 计算 PDP (利用互相关)
% ZC 序列的自相关特性接近冲激函数，所以互相关结果直接近似于 CIR (PDP)
[xc, lags] = xcorr(rx_signal, ref_seq);
pdp = abs(xc).^2;

% 归一化 PDP
pdp = pdp / max(pdp);
pdp_db = 10*log10(pdp);

% 找到主峰位置
[~, max_idx] = max(pdp);

% 截取主峰附近的窗口进行观察 (例如前后 200 个样点)
window = 100;
win_idxs = (max_idx - window) : (max_idx + window);
pdp_zoom = pdp(win_idxs);
pdp_db_zoom = pdp_db(win_idxs);
lags_zoom = lags(win_idxs);
time_axis_us = (0:length(win_idxs)-1) * ts * 1e6; % 微秒

%% 4. 计算 RMS 时延扩展 (RMS Delay Spread)
% 设定一个阈值，滤除噪声底噪 (例如 -20dB)
threshold_db = -20;
valid_indices = pdp_db_zoom > threshold_db;

if sum(valid_indices) < 2
    disp('Warning: Only 1 significant path detected (Line-of-Sight/Cable). RMS Delay ~ 0.');
    rms_delay_spread = 0;
    mean_delay = 0;
else
    pdp_linear = pdp_zoom(valid_indices);
    t_axis = time_axis_us(valid_indices);
    
    % Force column vectors
    if isrow(pdp_linear), pdp_linear = pdp_linear.'; end
    if isrow(t_axis), t_axis = t_axis.'; end
    
    total_power = sum(pdp_linear);
    mean_delay = sum(pdp_linear .* t_axis) / total_power;
    second_moment = sum(pdp_linear .* (t_axis.^2)) / total_power;
    
    % RMS Delay Spread
    rms_delay_spread = sqrt(abs(second_moment - mean_delay.^2));
end

%% 5. 估计信道频域响应 (H)
% 对 CIR (相关峰附近) 做 FFT
cir_window = xc(max_idx-32 : max_idx+31); % 取64点窗
H_est = fft(cir_window);
H_mag_db = 20*log10(abs(H_est));
f_axis = linspace(-fs/2, fs/2, length(H_est)) / 1e6; % MHz

%% 6. 绘图
f = figure('visible', 'off', 'Position', [100, 100, 1000, 500]);

% A. PDP
subplot(1, 2, 1);
plot(time_axis_us, pdp_db_zoom, 'b-o', 'MarkerSize', 3);
hold on;
yline(threshold_db, 'r--', 'Noise Threshold');
title(['Real Data PDP (RMS Delay: ' num2str(rms_delay_spread, '%.3f') ' \mus)']);
xlabel('Delay (\mus)'); ylabel('Normalized Power (dB)');
grid on;
legend('Measured PDP', 'Threshold');

% B. Frequency Response
subplot(1, 2, 2);
plot(f_axis, fftshift(H_mag_db), 'LineWidth', 1.5);
title('Estimated Channel Frequency Response');
xlabel('Frequency (MHz)'); ylabel('Magnitude (dB)');
grid on;
axis tight;

saveas(f, 'real_data_analysis.png');
disp(['Analysis Complete.']);
disp(['Detected Channel Type: ',LinkTypeDecision(rms_delay_spread)]);

function type = LinkTypeDecision(rms)
    if rms < 0.05
        type = 'Pure Cable / Perfect LOS (Flat Fading)';
    elseif rms < 0.5
        type = 'Typical Indoor / Lab Environment';
    else
        type = 'Rich Multipath / Outdoor';
    end
end
