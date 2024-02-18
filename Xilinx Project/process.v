`timescale 1ns / 1ps

module process(
	input clk,				// clock 
	input [23:0] in_pix,	// valoarea pixelului de pe pozitia [in_row, in_col] din imaginea de intrare (R 23:16; G 15:8; B 7:0)
	output reg [5:0] row, col, 	// selecteaza un rand si o coloana din imagine
	output reg out_we, 			// activeaza scrierea pentru imaginea de iesire (write enable)
	output reg [23:0] out_pix,	// valoarea pixelului care va fi scrisa in imaginea de iesire pe pozitia [out_row, out_col] (R 23:16; G 15:8; B 7:0)
	output reg mirror_done,		// semnaleaza terminarea actiunii de oglindire (activ pe 1)
	output reg gray_done,		// semnaleaza terminarea actiunii de transformare in grayscale (activ pe 1)
	output reg filter_done);	// semnaleaza terminarea actiunii de aplicare a filtrului de sharpness (activ pe 1)

// TODO add your finite state machines here
	reg[1:0] process_state = 0, process_nstate = 0;// reprezentarea starii automatului procesului
	reg[5:0] next_row = 0, next_col = 0;
	reg m_done = 0, g_done = 0, f_done = 0;
	
	reg[1:0] mirror_state = 0, mirror_nstate = 0;//elementele folosite in procesul mirror
	reg[23:0] mirror_mem, mirror_mem2;
		
	wire[7:0] R, G, B;//elementele folosite la procesul gray
	wire[8:0] gray_val;
	reg[7:0] gray_max, gray_min;
	
	reg[7:0] neighbor_matrix[2:0][2:0];//elementele folosite la procesul filter
	reg[7:0] prev_row[63:0];
	reg[3:0] filter_state = 0, filter_nstate = 0;
	reg[12:0] filter_sum;
	reg shift_done;
	integer i, j;
	
	assign R = in_pix[23:16];//alocarea valoriilor elementelor de tip wire
	assign G = in_pix[15:8];
	assign B = in_pix[7:0];
	assign gray_val = (gray_max+gray_min)/2;
	
	always @(posedge clk) begin
		process_state <= process_nstate;
		mirror_state <= mirror_nstate;
		filter_state = filter_nstate;
		row <= next_row;
		col <= next_col;
	end
	
	always @(*) begin
		out_pix = 0;
		out_we = 0;
		case (process_state)
			0:begin
				mirror_done = 0;
				gray_done = 0;
				filter_done = 0;
				row = 0;
				col = 0;
				for(i = 0; i < 64; i=i+1)begin
					prev_row[i] = 0;
				end
				process_nstate = 1;
			end
			1: begin 
				if(m_done == 0) begin
					case (mirror_state)
						0: begin mirror_mem = in_pix;
							next_row = 63-row;
							mirror_nstate = 1;
						end
						1: begin out_pix = mirror_mem;
							out_we = 1;
							mirror_mem2 = in_pix;
							next_row = 63-row;
							mirror_nstate = 2;
						end
						2: begin mirror_nstate = 0;
							out_pix = mirror_mem2;
							out_we = 1;
							if(row == 31) begin
								next_row = 0;
								if(col == 63) begin
									next_col = 0;
									m_done = 1;
								end else begin
									next_col = col+1;
								end
							end else begin
								next_row = row+1;
							end
						end
					endcase
				end else begin
					process_nstate = 2;
					mirror_done = 1;
				end
			end
			2: begin
				if (g_done == 0) begin
					if((R>G)&&(R>B)) begin
						gray_max = R;
						if(G<B) begin
							gray_min = G;
						end else begin
							gray_min = B;
						end
					end else if(G>B) begin
						gray_max = G;
						if(R<B) begin
							gray_min = R;
						end else begin
							gray_min = B;
						end
					end else begin
						gray_max = B;
						if(G<R) begin
							gray_min = G;
						end else begin
							gray_min = R;
						end
					end
					out_pix = {8'b0, gray_val[7:0], 8'b0};
					out_we = 1;
					if(col == 63) begin
						next_col = 0;
						if(row == 63) begin
							next_row = 0;
							g_done = 1;
						end else begin
							next_row = row+1;
						end
					end else begin
						next_col = col+1;
					end
				end else begin
					gray_done = 1;
					process_nstate = 3;
					next_row = 0;
					next_col = 0;
				end
			end
			3:begin
				if(f_done == 0) begin
					case(filter_state)
						0:begin //starea "new line"
							neighbor_matrix[0][0] = 0;
							neighbor_matrix[1][0] = 0;
							neighbor_matrix[2][0] = 0;
							neighbor_matrix[0][1] = prev_row[0];
							neighbor_matrix[0][2] = prev_row[1];
							neighbor_matrix[1][1] = G;
							if(row == 63) begin
								neighbor_matrix[2][1] = 0;
								neighbor_matrix[2][2] = 0;
								next_col = col+1;
								filter_nstate = 3;
							end else begin
								next_row = row+1;
								filter_nstate = 1;
							end
						end
						1:begin //urmatoarele 3 stari sunt pentru salvarea valorilor respective locatiilor in neighbor_matrix
							neighbor_matrix[2][1] = G;
							next_col = col+1;
							filter_nstate = 2;
						end
						2:begin
							neighbor_matrix[2][2] = G;
							next_row = row-1;
							filter_nstate = 3;
						end
						3:begin
							neighbor_matrix[1][2] = G;
							next_col = col-1;
							filter_sum = 0;
							filter_nstate = 4;
						end
						4:begin //starea "third act climax" in care neighbor_matrix a fost pregatta, se fac toate calcularile si apoi facem totul din nou
							prev_row[col] = G;
							filter_sum = 9*neighbor_matrix[1][1];
							for(i = 0; i < 3; i=i+1)begin
								for(j = 0; j < 3; j=j+1)begin
									if((i != 1)&&(j != 1))begin
										filter_sum = filter_sum - neighbor_matrix[i][j];
									end
								end
							end
							if(filter_sum > 255)begin
								filter_sum = 255;
							end
							out_pix = {8'b0, filter_sum[7:0], 8'b0};
							out_we = 1;
							shift_done = 0;
							filter_nstate = 5;
						end
						5:begin //starea "epi/pro-log" unde, dupa ce calcularile au fost facute, se trece la urmatorul pixel
							if(shift_done == 0)begin
								for(i = 0; i < 3; i=i+1)begin
									for(j = 0; j < 2; j=j+1)begin
										neighbor_matrix[i][j] = neighbor_matrix[i][j+1];
									end
								end
								shift_done = 1; //pentru a nu face shifatarea de doua ori inainte ca ceasul sa ia valoarea 1 si toate starile sa-si ia valorile urmatoare
							end
							if(col == 63)begin
								next_col = 0;
								if(row == 63)begin
									next_row = 0;
									f_done = 1;
								end else begin
									next_row = row+1;
									filter_nstate = 0;
								end
							end else begin
								next_col = col+1;
								if(col == 62)begin
									for(i = 0; i < 3; i=i+1)begin
										neighbor_matrix[i][2] = 0;
									end
									filter_sum = 0;
									filter_nstate = 4;
								end else if(row == 63)begin
									neighbor_matrix[2][2] = 0;
									neighbor_matrix[0][2] = prev_row[col+2];
									next_col = col+2;
									filter_nstate = 3;
								end else begin
									neighbor_matrix[0][2] = prev_row[col+2];
									next_col = col+2;
									next_row = row+1;
									filter_nstate = 2;
								end
							end
						end
					endcase
				end else begin
					filter_done = 1;
					process_nstate = 0;
				end
			end
		endcase
	end

endmodule
