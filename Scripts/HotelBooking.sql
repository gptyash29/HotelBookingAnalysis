
-- Core Tables Structure
-- Booking_Details: Central booking information
-- Guest_Info: Guest demographics linked via booking_id
-- Room_Details: Room allocation and changes
-- Meal_And_Stay_Details: Service preferences and ADR
-- Booking_Source_and_History: Channel and historical data
-- Reservation_Status: Current status and outcomes


-- Peak booking months and seasonality
WITH monthly_bookings AS (
    SELECT 
        arrival_date_year,
        arrival_date_month,
        COUNT(*) as total_bookings,
        SUM(is_canceled) as canceled_bookings,
        AVG(lead_time) as avg_lead_time,
        AVG(adr) as avg_daily_rate
    FROM booking_details bd
    JOIN meal_and_stay_details msd ON bd.booking_id = msd.booking_id
    GROUP BY arrival_date_year, arrival_date_month
)
SELECT *,
    (canceled_bookings * 100.0 / total_bookings) as cancellation_rate,
    LAG(total_bookings) OVER (ORDER BY arrival_date_year, arrival_date_month) as prev_month_bookings,
    ((total_bookings - LAG(total_bookings) OVER (ORDER BY arrival_date_year, arrival_date_month)) * 100.0 
     / LAG(total_bookings) OVER (ORDER BY arrival_date_year, arrival_date_month)) as month_growth_rate
FROM monthly_bookings
ORDER BY arrival_date_year, arrival_date_month;

-- Weekend vs Weekday analysis
SELECT 
    hotel,
    SUM(stays_in_weekend_nights) as total_weekend_nights,
    SUM(stays_in_week_nights) as total_weekday_nights,
    AVG(stays_in_weekend_nights) as avg_weekend_nights,
    AVG(stays_in_week_nights) as avg_weekday_nights,
    COUNT(*) as total_bookings
FROM booking_details
GROUP BY hotel;

-- Guest composition and outlier detection
WITH guest_stats AS (
    SELECT 
        booking_id,
        adults + children + babies as total_guests,
        adults, children, babies,
        CASE 
            WHEN children > 0 OR babies > 0 THEN 'Family'
            WHEN adults = 1 THEN 'Solo'
            WHEN adults = 2 THEN 'Couple'
            ELSE 'Group'
        END as guest_type_category
    FROM guest_info
)
SELECT 
    guest_type_category,
    COUNT(*) as booking_count,
    AVG(total_guests) as avg_party_size,
    MIN(total_guests) as min_party_size,
    MAX(total_guests) as max_party_size,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_guests) as median_party_size
FROM guest_stats
GROUP BY guest_type_category;

-- Special requests analysis by customer type
SELECT 
    bsh.customer_type,
    COUNT(*) as total_bookings,
    AVG(msd.total_of_special_requests) as avg_special_requests,
    AVG(msd.required_car_parking_spaces) as avg_parking_requests,
    SUM(CASE WHEN msd.total_of_special_requests > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as pct_with_special_requests
FROM booking_source_and_history bsh
JOIN meal_and_stay_details msd ON bsh.booking_id = msd.booking_id
GROUP BY bsh.customer_type
ORDER BY avg_special_requests DESC;

-- ADR analysis by multiple dimensions
SELECT 
    bd.hotel,
    msd.meal,
    bsh.customer_type,
    bsh.market_segment,
    COUNT(*) as booking_count,
    AVG(msd.adr) as avg_daily_rate,
    MIN(msd.adr) as min_adr,
    MAX(msd.adr) as max_adr,
    STDDEV(msd.adr) as adr_std_dev,
    SUM(msd.adr * (bd.stays_in_weekend_nights + bd.stays_in_week_nights)) as total_revenue
FROM booking_details bd
JOIN meal_and_stay_details msd ON bd.booking_id = msd.booking_id
JOIN booking_source_and_history bsh ON bd.booking_id = bsh.booking_id
WHERE bd.is_canceled = 0
GROUP BY bd.hotel, msd.meal, bsh.customer_type, bsh.market_segment
ORDER BY avg_daily_rate DESC;

-- Cancellation impact analysis
WITH cancellation_analysis AS (
    SELECT 
        bd.hotel,
        bd.arrival_date_month,
        COUNT(*) as total_bookings,
        SUM(bd.is_canceled) as canceled_bookings,
        SUM(CASE WHEN bd.is_canceled = 0 THEN msd.adr * (bd.stays_in_weekend_nights + bd.stays_in_week_nights) ELSE 0 END) as actual_revenue,
        SUM(msd.adr * (bd.stays_in_weekend_nights + bd.stays_in_week_nights)) as potential_revenue
    FROM booking_details bd
    JOIN meal_and_stay_details msd ON bd.booking_id = msd.booking_id
    GROUP BY bd.hotel, bd.arrival_date_month
)
SELECT *,
    (canceled_bookings * 100.0 / total_bookings) as cancellation_rate,
    (potential_revenue - actual_revenue) as lost_revenue,
    ((potential_revenue - actual_revenue) * 100.0 / potential_revenue) as revenue_loss_pct
FROM cancellation_analysis
ORDER BY lost_revenue DESC;

-- Channel performance analysis
SELECT 
    bsh.distribution_channel,
    bsh.market_segment,
    COUNT(*) as total_bookings,
    SUM(bd.is_canceled) as canceled_bookings,
    (SUM(bd.is_canceled) * 100.0 / COUNT(*)) as cancellation_rate,
    AVG(bd.lead_time) as avg_lead_time,
    AVG(msd.adr) as avg_adr,
    SUM(CASE WHEN bsh.is_repeated_guest = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as repeat_guest_rate
FROM booking_source_and_history bsh
JOIN booking_details bd ON bsh.booking_id = bd.booking_id
JOIN meal_and_stay_details msd ON bd.booking_id = msd.booking_id
GROUP BY bsh.distribution_channel, bsh.market_segment
ORDER BY total_bookings DESC;

-- Repeat guest behavior analysis
SELECT 
    CASE WHEN bsh.is_repeated_guest = 1 THEN 'Repeat Guest' ELSE 'First Time Guest' END as guest_category,
    COUNT(*) as total_bookings,
    AVG(bd.lead_time) as avg_lead_time,
    AVG(msd.adr) as avg_adr,
    (SUM(bd.is_canceled) * 100.0 / COUNT(*)) as cancellation_rate,
    AVG(msd.total_of_special_requests) as avg_special_requests,
    AVG(bd.stays_in_weekend_nights + bd.stays_in_week_nights) as avg_stay_length
FROM booking_source_and_history bsh
JOIN booking_details bd ON bsh.booking_id = bd.booking_id
JOIN meal_and_stay_details msd ON bd.booking_id = msd.booking_id
GROUP BY bsh.is_repeated_guest;

-- Room type allocation accuracy
SELECT 
    rd.reserved_room_type,
    rd.assigned_room_type,
    COUNT(*) as allocation_count,
    CASE WHEN rd.reserved_room_type = rd.assigned_room_type THEN 'Match' ELSE 'Different' END as allocation_status
FROM room_details rd
JOIN booking_details bd ON rd.booking_id = bd.booking_id
WHERE bd.is_canceled = 0
GROUP BY rd.reserved_room_type, rd.assigned_room_type
ORDER BY allocation_count DESC;

-- Booking changes impact on cancellations
SELECT 
    rd.booking_changes,
    COUNT(*) as total_bookings,
    SUM(bd.is_canceled) as canceled_bookings,
    (SUM(bd.is_canceled) * 100.0 / COUNT(*)) as cancellation_rate,
    AVG(msd.adr) as avg_adr
FROM room_details rd
JOIN booking_details bd ON rd.booking_id = bd.booking_id
JOIN meal_and_stay_details msd ON bd.booking_id = msd.booking_id
GROUP BY rd.booking_changes
ORDER BY rd.booking_changes;