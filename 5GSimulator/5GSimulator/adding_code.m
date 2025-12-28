%一些增添的代码
 % %% 调用Matlab自带的WiNNer信道函数
 %        cfgWim = winner2.wimparset;
 %        samplingRate = simParams.modulation.samplingRate;
 %        cfgWim.CenterFrequency = 2.5e9; % 设置中心频率
 %        cfgWim.DelaySamplingInterval = 1/samplingRate;
 %        BSAA = winner2.AntennaArray();
 %        MSAA = winner2.AntennaArray();
 %        MSIdx = [1];
 %        BSIdx = {1};
 %        NL = 1; % 单径
 %        rndSeed = 5;
 %        layoutpar = winner2.layoutparset(MSIdx,BSIdx,NL,[BSAA,MSAA],[],rndSeed);
 %        layoutpar.ScenarioVector = [4]; %1=A1, 2=A2, 3=B1, 4=B2, 5=B3, 6=B4, 10=C1, 11=C2, 12=C3, 13=C4, 14=D1, 15=D2a
 %        layoutpar.PropagConditionVector = [0]; %LOS = 1 and NLOS = 0
 %        [H,pathdealy,~] = winner2.wim(cfgWim,layoutpar);
 %        [~, ~, row, col] = size(H{1,1});
 %        A = zeros(row, col);
 %        % 取出信道矩阵
 %        for ii = 1:row
 %            for jj = 1:col
 %                A(ii, jj) = H{1,1}(1,1,ii,jj);
 %            end
 %        end
 %        PDP_mat = mean(A');
 %        PDP_mat = abs(PDP_mat).^2;   
 %        PDP_mat = normalize(PDP_mat,'range');
 %        figure(5)
 %        stem(pathdealy/1e-6, PDP_mat)
 %        xlabel('delay[s]')
 %        ylabel('Power Delay Profile')
 %        title('Matlab自带的WINNER-II信道PDP')

        % figure(1)
        % plot(Frequency,abs(FrequencyCorrelation));
        % ylabel('|Frequency Correlation|');
        % xlabel('Frequency (Hz)');
        % title('Estimilate')
        % 
        % figure(2)
        % Tau = (0:(length(primaryLink.Channel.Implementation.PowerDelayProfileNormalized))-1)*primaryLink.Channel.PHY.dt;
        % PowerDelayProfile = PDP_normal(1:length(primaryLink.Channel.Implementation.PowerDelayProfileNormalized));
        % % DesiredTemp = 10.^(primaryLink.Channel.PHY.DesiredPowerDelayProfiledB(1,:)/10);
        % % DesiredTemp = DesiredTemp/sum(DesiredTemp);
        % stem(primaryLink.Channel.PHY.DesiredPowerDelayProfiledB(2,:)/1e-6,DesiredTemp,'-x red');
        % hold on;
        % stem(Tau/1e-6,PowerDelayProfile,'-o  blue');
        % xlim([-primaryLink.Channel.PHY.dt/1e-6/2 Tau(end)/1e-6+primaryLink.Channel.PHY.dt/1e-6/2]);
        % xlabel('Delay [µs]');
        % ylabel('Power Delay Profile');
        % legend({'Desired Delay Taps','Chosen Delay Taps (due to sampling)'});
   
   % 绘制接收信号三维PSD
        % trans = [trans' zeros(1,dim - length(trans))];
        % receive = [receive' zeros(1,dim - length(receive))];

        % trans_PSD = reshape(trans(1:dim),simParams.modulation.nSymbolsTotal,simParams.modulation.numerOfSubcarriers);
        % receive_PSD = reshape(receive(1:dim),simParams.modulation.nSymbolsTotal,simParams.modulation.numerOfSubcarriers);
        % [m,n] = size(trans_PSD);
        % [X,Y] = meshgrid(1:n, 1:m);
        % figure(13)
        % mesh(Y,X,trans_PSD);
        % xlabel('OFDM symbols')
        % ylabel('Subcarrier Index')
        % zlabel('Transfer_PSD');
        % 
        % figure(14)
        % mesh(Y,X,receive_PSD);
        % xlabel('OFDM symbols')
        % ylabel('Subcarrier Index')
        % zlabel('Receive_PSD');