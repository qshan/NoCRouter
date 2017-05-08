import noc_params::*;

module switch_allocator #(
    parameter VC_TOTAL = 10,
    parameter PORT_NUM = 5,
    parameter VC_NUM = 2
)(
    input rst,
    input clk,
    /*
    TODO: make on_off_i compatible with the port coming out
    of the input_block module of the downstream router
    */
    input on_off_i [PORT_NUM-1:0][VC_NUM-1:0],
    input_block2switch_allocator.switch_allocator ib_if,
    switch_allocator2crossbar.switch_allocator xbar_if,
    output logic valid_flit_o [PORT_NUM-1:0]    //to the downstream router
);

    logic [VC_NUM-1:0] input_port_req [PORT_NUM-1:0];
    logic [VC_NUM-1:0] granted_vc [PORT_NUM-1:0];
    logic [PORT_NUM-1:0][PORT_NUM-1:0] requests_cmd;
    logic [PORT_NUM-1:0][PORT_NUM-1:0] grants;

    genvar port_arb;
    generate
        for(port_arb=0; port_arb<PORT_NUM; port_arb++)
        begin: generate_input_port_arbiters
            round_robin_arbiter #(
                .AGENTS_NUM(VC_NUM)
            )
            round_robin_arbiter (
                .rst(rst),
                .clk(clk),
                .requests_i(input_port_req[port_arb]),
                .grants_o(granted_vc[port_arb])
            );
        end
    endgenerate

    separable_input_first_allocator #(
        .AGENTS_NUM(PORT_NUM),
        .RESOURCES_NUM(PORT_NUM)
    )
    separable_input_first_allocator (
        .rst(rst),
        .clk(clk),
        .requests_i(requests_cmd),
        .grants_o(grants)
    );

    always_comb
    begin
        for(int port = 0; port < PORT_NUM ; port = port + 1)
        begin
            ib_if.valid_sel[port] = 1'b0;
            valid_flit_o[port] = 1'b0;
            ib_if.vc_sel[port] = {VC_SIZE{1'b0}};
            xbar_if.input_vc_sel[port] = {PORT_SIZE{1'b0}};
            input_port_req[port] = {VC_NUM{1'b0}};
            requests_cmd[port]={PORT_NUM{1'b0}};
        end

        for(int port = 0; port < PORT_NUM; port = port + 1)
        begin
            for(int vc = 0; vc < VC_NUM; vc = vc + 1)
            begin
                if(ib_if.switch_request[port][vc] & on_off_i[ib_if.out_port[port][vc]][ib_if.downstream_vc[port][vc]])
                begin
                    input_port_req[port][vc] = 1'b1;
                end
            end
        end

        for(int port = 0; port < PORT_NUM; port = port + 1)
        begin
            for(int vc = 0; vc < VC_NUM; vc = vc + 1)
            begin
                if(granted_vc[port][vc])
                begin
                    requests_cmd[port][ib_if.out_port[port][vc]] = 1'b1;
                end
            end
        end

        for(int in = 0; in < PORT_NUM; in = in + 1)
        begin
            for(int out = 0; out < PORT_NUM; out = out + 1)
            begin
                if(grants[in][out])
                begin
                    for(int vc = 0; vc < VC_NUM; vc = vc + 1)
                    begin
                        if(granted_vc[in][vc])
                        begin
                            ib_if.vc_sel[out] = ib_if.downstream_vc[in][vc];
                        end
                    end
                    ib_if.valid_sel[in] = 1'b1;
                    valid_flit_o[out] = 1'b1;
                    xbar_if.input_vc_sel[out] = (PORT_SIZE)'(in);
                end
            end
        end
    end

endmodule