module bip_bip_streamer(
    input  logic        clk,
    input  logic        rst,
    input  logic [23:0] data_in,
    input  logic        done,
    output logic [3:0]  data_out,
    output logic        done_into_gpio
);

    logic [2:0] counter;       // 3-bit counter (0 to 5)
    logic [23:0] buffer;       // internal buffer to hold data_in
    logic        streaming;    // streaming state flag

    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            counter         <= 3'b0;
            buffer          <= 24'b0;
            data_out        <= 4'b0;
            done_into_gpio  <= 1'b0;
            streaming       <= 1'b0;
        end else begin
            if (done && !streaming) begin
                buffer    <= data_in;
                counter   <= 3'b0;
                streaming <= 1'b1;
                done_into_gpio <= 1'b0;
            end else if (streaming) begin
                case (counter)
                    3'd0: data_out <= buffer[23:20];
                    3'd1: data_out <= buffer[19:16];
                    3'd2: data_out <= buffer[15:12];
                    3'd3: data_out <= buffer[11:8];
                    3'd4: data_out <= buffer[7:4];
                    3'd5: data_out <= buffer[3:0];
                endcase

                if (counter == 3'd5) begin
                    streaming      <= 1'b0;
                    done_into_gpio <= 1'b1;  // signal streaming is complete
                end else begin
                    counter <= counter + 1;
                end
            end else begin
                done_into_gpio <= 1'b0;  // reset signal when not streaming
            end
        end
    end

endmodule 