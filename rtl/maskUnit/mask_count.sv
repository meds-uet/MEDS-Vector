`include "vector_mask_ops.svh"

module mask_count (

    input  logic [ELEN-1:0]        vs2_element_mask,
    input  logic [ELEN-1:0]        v0_element_mask,
    input  logic                   vm,            // 1 = unmasked, 0 = use v0.t
    input  logic                   is_vid,        // 1 = vid.v, 0 = viota.m
    input  logic [COUNT_WIDTH-1:0] element_base,  // Global index of element 0 in this slice
    input  logic [COUNT_WIDTH-1:0] count_in,      // Exclusive prefix count from earlier slices (from the top-level parallel-prefix network, NOT a neighbor chain)

    output logic [COUNT_WIDTH-1:0] count_local,   // Set-bit count of THIS slice only, independent of count_in
    output logic [ELEN-1:0][COUNT_WIDTH-1:0] result_element_count

);

    logic [ELEN-1:0] count_mask;

    logic [LOCAL_W-1:0] local_count;
    logic [LOCAL_W-1:0] local_prefix;


    // Select the mask bits that are actually active.
    always_comb begin
        if (vm)
            count_mask = vs2_element_mask;
        else
            count_mask = vs2_element_mask & v0_element_mask;
    end


    // Number of set bits in this slice. Depends only on this slice's own
    // mask bits -- every slice can compute this at the same time.
    always_comb begin
        local_count = LOCAL_W'($countones(count_mask));
    end


    // Expose the local count directly instead of folding it into a running
    // total ourselves; the top level combines every slice's count_local with
    // a parallel-prefix tree (mask_prefix) rather than a slice-to-slice chain.
    always_comb begin
        count_local = COUNT_WIDTH'(local_count);
    end


    // Generate one result for each element.
    //
    // viota.m uses the number of active bits before the current element.
    // vid.v simply writes the global element index.
    always_comb begin
        local_prefix         = '0;
        result_element_count = '0;

        for (int i = 0; i < ELEN; i++) begin

            if (is_vid)
                result_element_count[i] = element_base + COUNT_WIDTH'(i);
            else
                result_element_count[i] = count_in + COUNT_WIDTH'(local_prefix);

            // Include the current bit for the next element.
            local_prefix = local_prefix + LOCAL_W'(count_mask[i]);

        end
    end

endmodule
