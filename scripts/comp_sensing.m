% Get the image.
P = imread('../images/200px-mickey.jpg');
P = imresize(P, 0.4);
P = im2double(rgb2gray(P));
max_shift_amplitude = 1;

% Pad the image with a fixed boundary of 5 pixels.
P = padarray(P, [3, 3], 0.0);

% Constants.
D = dctmtx(86);
x = D*P;
x = x(:);
sigmaNoiseFraction = 0.05;
filename = ...
    '../results/moment_estimation/unknown_angles_and_shifts/5_percent_noise/';
lambda  = 0.1;
rel_tol = 200;
output_size = max(size(P));
height = size(P, 1);
width = size(P, 2);

% Number of angles list.
num_theta = [30 50 70 80 100 120];

parfor o=1:6
    theta_to_write = zeros(10, num_theta(o));
    amplitude = 10;

    % Write the original image.
    imwrite(P, strcat(filename,...
        num2str(num_theta(o)), '/original_image.png'));

    % Define ground truth angles and take the tomographic projection.
    theta = datasample(0:179, num_theta(o));  
    [projections, svector] = radon(P,theta);
    original_projections = projections;
    original_shifts = zeros(size(theta));
    
    % Shift each projection by an unknown amount.
    for i=1:size(projections, 2)
        original_shifts(i) = ...
            randi([-max_shift_amplitude, max_shift_amplitude]);
        projections(:, i) = circshift(projections(:, i), original_shifts(i)); 
    end
    theta_to_write(1, :) = theta;
    theta_to_write(6, :) = original_shifts;
 
    % Normalize s to a unit circle
    smax = max(abs(svector));
    svector = svector / smax;
    projection_length = size(projections, 1);

    % Add noise to projections.
    [projections, sigmaNoise] = add_noise(projections, sigmaNoiseFraction);
    
    % Initial error.
    disp(norm(projections - original_projections));
    
    estimated_shift_amounts = zeros(size(theta));
    
    % Estimate the shifts by keeping the center of mass in the center.
    for i=1:size(projections, 2)
        current_projection = projections(:, i);
        tot_mass = sum(current_projection(:));
        [ii,jj] = ...
            ndgrid(1:size(current_projection,1),1:size(current_projection,2));
        center_of_mass = sum(ii(:).*current_projection(:))/tot_mass;
        % disp(norm(projections(:, i) - original_projections(:, i)));
        shift_amount = round(((projection_length - 1)/2) - center_of_mass);
        if shift_amount > max_shift_amplitude
            shift_amount  = max_shift_amplitude;
        elseif shift_amount < -max_shift_amplitude
            shift_amount  = -max_shift_amplitude;
        end
        estimated_shift_amounts(i) = -shift_amount;
        projections(:, i) = circshift(projections(:, i), shift_amount); 
        % disp(norm(projections(:, i) - original_projections(:, i)));
    end
    
    % Error after distance correction.
    disp(norm(projections - original_projections));
    disp(sum(estimated_shift_amounts ~= original_shifts));
    theta_to_write(7, :) = estimated_shift_amounts;
    
    % Predict the angles using moment angle estimation.
    [projections, noisy_theta, projection_shifts] = ...
        SHARPord(projections, svector, sigmaNoise, max_shift_amplitude,...
        -estimated_shift_amounts');
    
    for i=1:size(projections, 2)
        projections(:, i) = circshift(projections(:, i), projection_shifts(i)); 
    end
    
    theta_to_write(8, :) = -projection_shifts;
    noisy_theta = noisy_theta';
    projection_shifts = projection_shifts';
    
    % Error after noise removal.
    disp(norm(projections - original_projections));
    disp(sum(projection_shifts ~= original_shifts));

    noisy_theta = noisy_theta + theta(1) - noisy_theta(1);
    noisy_theta = process_theta(noisy_theta);
    theta_to_write(2, :) = noisy_theta;
    relative_estimated_error = norm(noisy_theta - theta)/norm(theta);

    n = height*width;
    m = projection_length*size(noisy_theta, 2);

    % Start iteration.
    better_theta = noisy_theta;
    previous_error = inf;
    precision = 0.1;
    errors = [];

    % Reconstruct the images from projection.
    reconstructed_image = iradon(projections, noisy_theta, output_size);
    imwrite(reconstructed_image, ...
        strcat(filename, num2str(num_theta(o)), '/estimated_image.png'));

    for i=1:40
        y = projections(:);

        A = radonTransform(...
            better_theta, width, height, output_size, projection_length);
        At = A';

        %run the l1-regularized least squares solver
        [reconstructed_image, status]= ...
            l1_ls(A,At,m,n,y,lambda,rel_tol,true);

        % The error we optimise.
        function_error = norm(A*reconstructed_image - y).^2 + ...
            lambda*norm(reconstructed_image, 1);
        
        % Reconstruct the image.
        reconstructed_image = reshape(reconstructed_image, [height, width]);
        reconstructed_image = D'*reconstructed_image;
        reconstructed_image(reconstructed_image < 0) = 0;

        if function_error < previous_error
            noisy_theta = better_theta;
            previous_error = function_error;
            shifted_projections = projections;

            disp(function_error);
            errors = [errors function_error];

            % Do a brute force search on all angles.
            better_theta = ...
                best_angle_alternate(precision, amplitude, noisy_theta,...
                reconstructed_image, projections);
            
            % Do a brute force search on all shifts.
            [projections, best_shifts] = ...
                best_shifts_estimate(max_shift_amplitude, noisy_theta,...
                reconstructed_image, shifted_projections);
        else
            precision = precision/1.1;
            amplitude = amplitude/1.1;

            % Do a brute force search on all angles.
            better_theta = ...
                best_angle_alternate(precision, amplitude, noisy_theta,...
                reconstructed_image, projections);
            
            % Do a brute force search on all shifts.
            [projections, best_shifts] = ...
                best_shifts_estimate(max_shift_amplitude, noisy_theta,...
                reconstructed_image, shifted_projections);
        end
    end
    
    imwrite(reconstructed_image, ...
        strcat(filename, num2str(num_theta(o)), '/reconstructed.png'));
    
    better_theta = better_theta + theta(1) - better_theta(1);
    better_theta = process_theta(better_theta);
    theta_to_write(3, :) = better_theta;
    theta_to_write(9, :) = -best_shifts;
    
    relative_reconstructed_error = ...
        norm(better_theta - theta)/norm(theta);
    
    % Plot the function error.
    figure; plot(errors);
    saveas(gcf, ...
        strcat(filename, num2str(num_theta(o)), '/error.png'));
    
    % Write the thetas to csv file.
    theta_to_write(4, 1) = relative_estimated_error;
    theta_to_write(5, 1) = relative_reconstructed_error;
    csvwrite(strcat(filename,...
        num2str(num_theta(o)), '/thetas.csv'), theta_to_write);
end