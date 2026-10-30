% ============================================
% PRACTICA 4 - UART FPGA
% Operacion: x^(7/2)
% ============================================

clear
clc

PORT = "COM10";
BAUD = 9600;

clear s

% Abrir conexion
s = serialport(PORT, BAUD);
s.Timeout = 3;

pause(2);
flush(s);

disp("====================================");
disp("COMUNICACION FPGA - POTENCIA 7/2");
disp("MATLAB <-> ESP32 <-> DE10-Lite");
disp("====================================");

while true

    entrada = strtrim(input( ...
        'Ingrese numero entre 0-255 (q para salir): ', 's'));

    if strcmpi(entrada, 'q')
        break;
    end

    valor = str2double(entrada);

    if isnan(valor) || ~isfinite(valor) || ...
       valor < 0 || valor > 255 || valor ~= floor(valor)

        disp("Valor invalido");
        continue;
    end

    % Eliminar bytes anteriores
    flush(s, "input");

    % Enviar dato de 8 bits
    write(s, uint8(valor), "uint8");

    fprintf("\nNumero enviado: %d\n", valor);

    % Calculo esperado
    esperadoReal = valor^(7/2);
    esperadoEntero = floor(esperadoReal + 1e-7);

    % Recibir exactamente cuatro bytes
    bytes = uint8([]);
    t = tic;

    while numel(bytes) < 4 && toc(t) < 3

        disponibles = s.NumBytesAvailable;

        if disponibles > 0
            cantidad = min(disponibles, 4-numel(bytes));
            nuevos = read(s, cantidad, "uint8");
            bytes = [bytes; nuevos(:)];
        else
            pause(0.01);
        end
    end

    if numel(bytes) == 4

        % Reconstruccion little-endian
        respuesta = double(bytes(1)) + ...
                    double(bytes(2))*256 + ...
                    double(bytes(3))*65536 + ...
                    double(bytes(4))*16777216;

        fprintf("FPGA responde: %.0f\n", respuesta);
        fprintf("Resultado matematico: %.6f\n", esperadoReal);
        fprintf("Resultado entero esperado: %.0f\n", esperadoEntero);

        if respuesta == esperadoEntero
            disp("CORRECTO");
        else
            disp("ERROR: Respuesta incorrecta");
        end

    else
        fprintf("ERROR: Recibidos %d de 4 bytes\n", numel(bytes));
    end

    disp("------------------------------------");

end

clear s
disp("Comunicacion finalizada");