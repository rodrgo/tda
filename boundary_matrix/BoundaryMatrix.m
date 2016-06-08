classdef BoundaryMatrix
    properties
        m;
        complex_dimension;
	dimensions;
        matrix;
        low;
        low_star;
        left;
        alpha;
        beta;
        gamma;
        rho;

        % Keep track of positive, negatives, essentials
        negatives;
        positives;
        essentials;
    end

    methods
        function obj = BoundaryMatrix(stream, mode)
            if nargin == 1
                mode = 'plain';
            end
            if nargin > 0

                % Query stream from Javaplex
                import edu.stanford.math.plex4.*;
		if strcmp(mode, 'reduced')
			ccs = streams.utility.StreamUtility.getCompressedBoundaryMatrixRedHom(stream);
                	obj.m = stream.getSize() + 1; % Add dummy simplex
		else
			ccs = streams.utility.StreamUtility.getCompressedBoundaryMatrix(stream);
                	obj.m = stream.getSize();
		end

		% Create sparse boundary matrix
                array = ccs.get(0).toArray();
                rows = zeros(size(array));
                for i = 1:array.length
                    rows(i) = double(array(i));
                end
                array = ccs.get(1).toArray();
                cols = zeros(size(array));
                for i = 1:array.length
                    cols(i) = double(array(i));
                end
                obj.matrix = sparse(rows, cols, ones(size(rows)), obj.m, obj.m);
                assert(istriu(obj.matrix));

                % Get dimension of the complex
		obj.dimensions = sum(obj.matrix);
                obj.complex_dimension = max(obj.dimensions);

                if ~strcmp(mode, 'plain')
                  % Upper and lower bounds
                  obj = obj.create_low();
                  obj = obj.create_alpha();
                  obj = obj.create_left();
                  obj = obj.create_beta();

                  % Optimisers
                  obj = obj.create_low_star();
                  obj = obj.create_rho();
                end
            end
        end

        function l = get_low(obj, j)
            if any(obj.matrix(:, j))
                l = find(obj.matrix(:, j), 1, 'last');
            else
                l = 0;
            end
        end

        function l = get_left(obj, i)
            if any(obj.matrix(i, :))
                l = find(obj.matrix(i, :), 1, 'first');
            else
                l = 0;
            end
        end

        function obj = create_low(obj)
            obj.low = zeros(1, obj.m);
            for j = 1:obj.m
                obj.low(j) = obj.get_low(j);
            end
        end

        function obj = create_low_star(obj)
            obj.low_star = -1*ones(1, obj.m);
            arglow = zeros(obj.m, 1);
            for j = 1:obj.m
                if obj.low(j) > obj.alpha(j)
                   if arglow(obj.low(j)) == 0
                       obj.low_star(j) = obj.low(j);
                       arglow(obj.low(j)) = j;
                   end
                end
            end
        end

        function obj = create_left(obj)
            obj.left = zeros(obj.m, 1);
            for i = 1:obj.m
                obj.left(i) = obj.get_left(i);
            end
        end

        function obj = create_alpha(obj)
            obj.alpha = zeros(1, obj.m);
            for j = 1:obj.m
              obj.alpha(j) = obj.low(j);
            end
        end

        function obj = create_rho(obj)
            obj.rho = zeros(obj.m, 1);
	    obj.rho(1) = 0 + (obj.beta(1) > 0);
            for j = 2:obj.m
                if obj.beta(j) > 0
                        obj.rho(j) = obj.rho(j-1) + 1;
                else
                        obj.rho(j) = obj.rho(j-1) - 1;
                end
            end
        end

        function obj = create_beta(obj)
            obj.beta = zeros(obj.m, 1);
            for j = 1:obj.m
                lefts_in_col_j = find(obj.left == j);
                if ~isempty(lefts_in_col_j)
                    obj.beta(j) = max(lefts_in_col_j);
                end
            end
        end

        function obj = reduce_column(obj, j)
            if j > 1
                j0 = find(obj.low(1:j-1) ~= 0 & obj.low(1:(j-1)) == lows(j));
                while ~isempty(j0)
                    obj.matrix(:, j) = mod(obj.matrix(:, j) + obj.matrix(:, j0), 2);
                    obj.low(j) = obj.get_low(j);
                    j0 = find(obj.low(1:j-1) ~= 0 & obj.low(1:(j-1)) == obj.low(j));
                end
                obj.low(j) = obj.get_low(j);
            end
        end

        function [lows, t] = twist_reduction_sparse(obj)
            tic;
            R = obj.matrix;
            obj = obj.create_low();
            lows = obj.low;
            complex_dim = obj.complex_dimension;
            simplex_dim = obj.dimensions;
            L = zeros(obj.m, 1);
            for d = complex_dim:-1:1
                for j = 1:obj.m
                    if sum(simplex_dim(j)) == d
						% lows(j) == 0 iff j \in \positive
						%
						% L(lows(j)) == 0 iff \nexists j0 < j
						% s.t. low(j0) = low(j). i.e.
						% iff lows(j) = low_star(j)
                        while (lows(j) > 0) && (L(lows(j)) ~= 0)
                            j0 = L(lows(j));
                            R(:, j) = mod(R(:,j) + R(:,j0), 2);
                            % Update lows
                            if any(R(:, j))
                                lows(j) = find(R(:,j), 1, 'last');
                            else
                                lows(j) = 0;
                            end
                        end
                        if lows(j) > 0
                            i = lows(j);
                            L(i) = j;
                            R(:, i) = 0;
                        end
                    end
                end
            end
            t = toc;
        end

        function [lows, t] = standard_reduction_sparse(obj)
            tic;
            R = obj.matrix;
            obj = obj.create_low();
            lows = obj.low;
            for j = 1:obj.m
                j0 = find(lows(1:(j-1)) ~= 0 & lows(1:(j-1)) == lows(j));
                while ~isempty(j0)
                    R(:, j) = mod(R(:, j) + R(:, j0), 2);
                    if any(R(:, j))
                        lows(j) = find(R(:, j), 1, 'last');
                    else
                        lows(j) = 0;
                    end
                    j0 = find(lows(1:(j-1)) ~= 0 & lows(1:(j-1)) == lows(j));
                end
            end
            %idx = find(lows);
            %low_mask = sparse(lows(idx), idx, ones(size(idx)), obj.m, obj.m);
            t = toc;
        end

        function [lows, t] = standard_reduction_sparse_opt(obj)
            tic;
            R = obj.matrix;
            obj = obj.create_low();
            lows = obj.low;
            L = zeros(size(lows)); % lowstar(i) == L(i)
            for j = 1:obj.m
                R_j = R(:, j);
                while (lows(j) > 0 && (L(lows(j)) ~= 0))
                    j0 = L(lows(j));
					R_j = mod(R_j + R(:, j0), 2);
					if any(R_j)
						lows(j) = find(R_j, 1, 'last');
					else
						lows(j) = 0;
					end
                end
                R(:, j) = R_j;
                if lows(j) > 0
                    L(lows(j)) = j;
                end
            end
            t = toc;
        end

        function [lows, t] = standard_reduction_dense_opt(obj)
            tic;
            R = full(obj.matrix);
            obj = obj.create_low();
            lows = obj.low;
            L = zeros(size(lows));
            for j = 1:obj.m
                while (lows(j) > 0 && (L(lows(j)) ~= 0))
                    j0 = L(lows(j));
					R(:, j) = mod(R(:, j) + R(:, j0), 2);
					if any(R(:, j))
						lows(j) = find(R(:, j), 1, 'last');
					else
						lows(j) = 0;
					end
                end
                if lows(j) > 0
                    L(lows(j)) = j;
                end
            end
            t = toc;
        end

        %% Masks
        %  Create matrix masks for visualisation

        function mask = get_low_star_mask(obj)
            idx = find(obj.low_star ~= -1);
            mask = sparse(obj.low_star(idx), idx, ones(size(idx)), obj.m, obj.m);
        end

        function mask = get_alpha_mask(obj)
            idx = find(obj.alpha);
            mask = sparse(obj.alpha(idx), idx, ones(size(idx)), obj.m, obj.m);
        end

        function mask = get_beta_mask(obj)
            idx = find(obj.beta);
            mask = sparse(obj.beta(idx), idx, ones(size(idx)), obj.m, obj.m);
        end

        function mask = get_left_mask(obj)
            idx = find(obj.left);
            mask = sparse(idx, obj.left(idx), ones(size(idx)), obj.m, obj.m);
        end

        function mask = get_matrix_mask_pruned_by_beta(obj)
            rows = zeros(1, obj.m);
            cols = zeros(1, obj.m);
            l = 1;
            for j = 1:obj.m
                supp_j = find(obj.matrix(:, j));
                for i = 1:length(supp_j)
                    row = supp_j(i);
                    if obj.beta(j) == 0 || (obj.beta(j) > 0 && row >= obj.beta(j))
                        rows(l) = row;
                        cols(l) = j;
                        l = l + 1;
                    end
                end
            end
            mask = sparse(rows(1:l-1), cols(1:l-1), ones(1, l-1), obj.m, obj.m);
        end
    end
end