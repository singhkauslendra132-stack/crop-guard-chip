`default_nettype none

module tt_um_crop_guard (
    input  wire [7:0] ui_in,    // 0=Solid, 1=Motion, 2=Sensor/Auto Mode, 3=1.45 rad (1) vs 0.15 rad (0)
    output wire [7:0] uo_out,   // 0=q0, 1=q1, 2=Safe Status (q2), 3=Alarm Trigger (q3)
    input  wire [7:0] uio_in,   // अतिरिक्त सेंसर सीड
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    assign uio_out = 8'b00000000;
    assign uio_oe  = 8'b00000000;
    wire _unused   = &{ena, ui_in[7:4], uio_in[7:3], 1'b0};

    reg [15:0] q_lfsr;
    reg [3:0]  c_out;

    // 1. बाहरी इनपुट पिन से बिना ब्रैकेट के सटीक 1-बिट निकालना
    wire in_solid  = ui_in & 1'b1;
    wire in_motion = (ui_in >> 1) & 1'b1;
    wire in_mode   = (ui_in >> 2) & 1'b1;
    wire test_rad  = (ui_in >> 3) & 1'b1; // 1 = 1.45 rad (नीलगाय), 0 = 0.15 rad (तेज़ हवा)

    // 2. LFSR रजिस्टर से सटीक 1-बिट निकालना (Phase 1 & 2: Night/Fog Baseline)
    wire l0  = q_lfsr & 1'b1;
    wire l1  = (q_lfsr >> 1) & 1'b1;
    wire l2  = (q_lfsr >> 2) & 1'b1;
    wire l3  = (q_lfsr >> 3) & 1'b1;
    wire l4  = (q_lfsr >> 4) & 1'b1;
    wire l5  = (q_lfsr >> 5) & 1'b1;
    wire l6  = (q_lfsr >> 6) & 1'b1;
    wire l7  = (q_lfsr >> 7) & 1'b1;
    wire l15 = (q_lfsr >> 15) & 1'b1;

    // 1.45 rad पर उच्च संभाव्यता (OR गेट) तथा 0.15 rad पर अति-न्यून संभाव्यता (4-बिट AND गेट)
    wire prob_q0 = test_rad ? (l0 | l1) : (l0 & l1 & l2 & l3);
    wire prob_q1 = test_rad ? (l2 | l3) : (l4 & l5 & l6 & l7);

    wire q0_state = in_mode ? in_solid  : prob_q0;
    wire q1_state = in_mode ? in_motion : prob_q1;

    // 3. Phase 3 - Case A: Solid Body AND Motion (ccx q0, q1, q3)
    wire q3_alarm_trigger = q0_state & q1_state;

    // 4. Phase 3 - Case B: No Solid Body (x q0 -> cx q0, q2 -> x q0)
    wire q0_inverted    = ~q0_state;
    wire q2_safe_status = q0_inverted;
    wire q0_restored    = ~q0_inverted;

    // 5. Phase 4: Quantum Measurement (measure q -> c)
    always @(posedge clk) begin
        if (!rst_n) begin
            q_lfsr <= 16'hACE1 ^ {13'd0, uio_in[2:0]};
            c_out  <= 4'b0000;
        end else begin
            q_lfsr <= {q_lfsr[14:0], (l0 ^ l2 ^ l3 ^ l15)};
            c_out  <= {q3_alarm_trigger, q2_safe_status, q1_state, q0_restored};
        end
    end

    assign uo_out = {4'b0000, c_out};

endmodule
