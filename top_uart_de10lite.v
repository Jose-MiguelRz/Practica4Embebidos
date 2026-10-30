module top_uart_de10lite(
    input wire CLOCK_50,
    input wire RESET_N,
    input wire UART_RX,
    output wire UART_TX
);

wire reset = ~RESET_N;

wire [7:0] rx_data;
wire rx_done;

reg [7:0] tx_data;
reg tx_start;
wire tx_busy;

uart_rx #(
    .CLK_FREQ(50000000),
    .BAUD_RATE(9600)
) RX0 (
    .clk(CLOCK_50),
    .reset(reset),
    .rx(UART_RX),
    .data_out(rx_data),
    .data_valid(rx_done)
);

uart_tx #(
    .CLK_FREQ(50000000),
    .BAUD_RATE(9600)
) TX0 (
    .clk(CLOCK_50),
    .reset(reset),
    .tx_start(tx_start),
    .data_in(tx_data),
    .tx(UART_TX),
    .busy(tx_busy)
);

// Estados del procesamiento
localparam [3:0]
    S_IDLE      = 4'd0,
    S_POWER     = 4'd1,
    S_ROOT_INIT = 4'd2,
    S_ROOT      = 4'd3,
    S_SEND      = 4'd4,
    S_TX_START  = 4'd5,
    S_TX_DONE   = 4'd6;

reg [3:0] state;

// Calculo de x^7
reg [7:0] input_value;
reg [55:0] power_value;
reg [2:0] power_count;

// Raiz cuadrada entera de 56 bits
reg [55:0] radicand;
reg [29:0] remainder;
reg [27:0] root;
reg [4:0] root_count;

// Resultado de 32 bits
reg [31:0] result;
reg [1:0] byte_index;

// Variables auxiliares combinacionales
wire [29:0] next_remainder;
wire [29:0] trial_value;

assign next_remainder =
    {remainder[27:0], radicand[55:54]};

assign trial_value = {root, 2'b01};

// Seleccionar uno de los 4 bytes
always @(*) begin
    case (byte_index)
        2'd0: tx_data = result[7:0];
        2'd1: tx_data = result[15:8];
        2'd2: tx_data = result[23:16];
        2'd3: tx_data = result[31:24];
        default: tx_data = 8'd0;
    endcase
end

always @(posedge CLOCK_50 or posedge reset) begin

    if (reset) begin
        state <= S_IDLE;
        tx_start <= 1'b0;

        input_value <= 0;
        power_value <= 0;
        power_count <= 0;

        radicand <= 0;
        remainder <= 0;
        root <= 0;
        root_count <= 0;

        result <= 0;
        byte_index <= 0;

    end else begin

        tx_start <= 1'b0;

        case (state)

            // Esperar un byte desde ESP32
            S_IDLE: begin
                if (rx_done) begin
                    input_value <= rx_data;
                    power_value <= 56'd1;
                    power_count <= 0;
                    state <= S_POWER;
                end
            end

            // Potencia: x*x*x*x*x*x*x
            S_POWER: begin
                if (power_count < 3'd7) begin
                    power_value <=
                        power_value * input_value;

                    power_count <= power_count + 1'b1;
                end else begin
                    state <= S_ROOT_INIT;
                end
            end

            // Preparar raiz cuadrada
            S_ROOT_INIT: begin
                radicand <= power_value;
                remainder <= 0;
                root <= 0;
                root_count <= 0;
                state <= S_ROOT;
            end

            // Raiz cuadrada binaria, 28 iteraciones
            S_ROOT: begin

                radicand <= {radicand[53:0], 2'b00};

                if (next_remainder >= trial_value) begin
                    remainder <=
                        next_remainder - trial_value;

                    root <= {root[26:0], 1'b1};

                    if (root_count == 5'd27) begin
                        result <=
                            {4'b0000, root[26:0], 1'b1};

                        byte_index <= 0;
                        state <= S_SEND;
                    end

                end else begin
                    remainder <= next_remainder;

                    root <= {root[26:0], 1'b0};

                    if (root_count == 5'd27) begin
                        result <=
                            {4'b0000, root[26:0], 1'b0};

                        byte_index <= 0;
                        state <= S_SEND;
                    end
                end

                root_count <= root_count + 1'b1;
            end

            // Solicitar transmision UART
            S_SEND: begin
                if (!tx_busy) begin
                    tx_start <= 1'b1;
                    state <= S_TX_START;
                end
            end

            // Esperar que UART comience
            S_TX_START: begin
                if (tx_busy) begin
                    state <= S_TX_DONE;
                end
            end

            // Esperar que termine el byte
            S_TX_DONE: begin
                if (!tx_busy) begin

                    if (byte_index == 2'd3) begin
                        state <= S_IDLE;
                    end else begin
                        byte_index <= byte_index + 1'b1;
                        state <= S_SEND;
                    end
                end
            end

            default: state <= S_IDLE;

        endcase
    end
end

endmodule