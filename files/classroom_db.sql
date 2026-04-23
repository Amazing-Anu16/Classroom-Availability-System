-- ============================================================
--  CLASSROOM MANAGEMENT SYSTEM — MySQL Schema
--  Theme: Academic / Institutional
-- ============================================================

CREATE DATABASE IF NOT EXISTS classroom_mgmt;
USE classroom_mgmt;

-- ─────────────────────────────────────────────
-- 1. DEPARTMENTS
-- ─────────────────────────────────────────────
CREATE TABLE departments (
    dept_id       INT AUTO_INCREMENT PRIMARY KEY,
    dept_name     VARCHAR(100) NOT NULL UNIQUE,
    dept_code     VARCHAR(10)  NOT NULL UNIQUE,
    hod_name      VARCHAR(100),
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─────────────────────────────────────────────
-- 2. YEARS / CLASSES
-- ─────────────────────────────────────────────
CREATE TABLE years (
    year_id       INT AUTO_INCREMENT PRIMARY KEY,
    dept_id       INT NOT NULL,
    year_number   TINYINT NOT NULL COMMENT '1=FY, 2=SY, 3=TY, 4=Final',
    division      CHAR(1) NOT NULL DEFAULT 'A',
    total_students INT DEFAULT 60,
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id) ON DELETE CASCADE,
    UNIQUE KEY uq_year_div (dept_id, year_number, division)
);

-- ─────────────────────────────────────────────
-- 3. FACULTY
-- ─────────────────────────────────────────────
CREATE TABLE faculty (
    faculty_id    INT AUTO_INCREMENT PRIMARY KEY,
    dept_id       INT NOT NULL,
    full_name     VARCHAR(100) NOT NULL,
    employee_code VARCHAR(20)  NOT NULL UNIQUE,
    email         VARCHAR(150) UNIQUE,
    phone         VARCHAR(15),
    designation   ENUM('Professor','Associate Professor','Assistant Professor','Lecturer') DEFAULT 'Assistant Professor',
    is_active     TINYINT(1) DEFAULT 1,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);

-- ─────────────────────────────────────────────
-- 4. CLASSROOMS / LABS
-- ─────────────────────────────────────────────
CREATE TABLE classrooms (
    room_id       INT AUTO_INCREMENT PRIMARY KEY,
    room_code     VARCHAR(20)  NOT NULL UNIQUE  COMMENT 'e.g. B811, LAB201',
    building      VARCHAR(50)  NOT NULL,
    floor_number  TINYINT      NOT NULL,
    room_type     ENUM('Classroom','Lab','Seminar Hall','Auditorium') DEFAULT 'Classroom',
    seating_cap   INT          NOT NULL DEFAULT 60,
    has_projector TINYINT(1)   DEFAULT 1,
    has_ac        TINYINT(1)   DEFAULT 0,
    is_active     TINYINT(1)   DEFAULT 1
);

-- ─────────────────────────────────────────────
-- 5. SUBJECTS
-- ─────────────────────────────────────────────
CREATE TABLE subjects (
    subject_id    INT AUTO_INCREMENT PRIMARY KEY,
    dept_id       INT NOT NULL,
    year_number   TINYINT NOT NULL,
    subject_name  VARCHAR(150) NOT NULL,
    subject_code  VARCHAR(20)  NOT NULL UNIQUE,
    credits       TINYINT DEFAULT 4,
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);

-- ─────────────────────────────────────────────
-- 6. TIMETABLE SLOTS  (pre-planned schedule)
-- ─────────────────────────────────────────────
CREATE TABLE timetable_slots (
    slot_id       INT AUTO_INCREMENT PRIMARY KEY,
    room_id       INT NOT NULL,
    faculty_id    INT NOT NULL,
    subject_id    INT NOT NULL,
    year_id       INT NOT NULL,
    day_of_week   ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday') NOT NULL,
    start_time    TIME NOT NULL,
    end_time      TIME NOT NULL,
    semester      TINYINT NOT NULL DEFAULT 1,
    academic_year VARCHAR(9) NOT NULL DEFAULT '2024-25',
    FOREIGN KEY (room_id)    REFERENCES classrooms(room_id),
    FOREIGN KEY (faculty_id) REFERENCES faculty(faculty_id),
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id),
    FOREIGN KEY (year_id)    REFERENCES years(year_id),
    -- Prevent double-booking a room at the same time
    UNIQUE KEY uq_room_slot  (room_id, day_of_week, start_time, semester, academic_year),
    -- Prevent faculty from being in two places
    UNIQUE KEY uq_faculty_slot (faculty_id, day_of_week, start_time, semester, academic_year)
);

-- ─────────────────────────────────────────────
-- 7. LIVE SESSIONS  (real-time tracking)
-- ─────────────────────────────────────────────
CREATE TABLE live_sessions (
    session_id    INT AUTO_INCREMENT PRIMARY KEY,
    room_id       INT NOT NULL,
    faculty_id    INT NOT NULL,
    subject_id    INT NOT NULL,
    year_id       INT NOT NULL,
    slot_id       INT NULL COMMENT 'NULL if ad-hoc booking',
    session_date  DATE         NOT NULL DEFAULT (CURDATE()),
    check_in_time DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    check_out_time DATETIME    NULL,
    status        ENUM('ongoing','completed','cancelled') DEFAULT 'ongoing',
    notes         TEXT,
    FOREIGN KEY (room_id)    REFERENCES classrooms(room_id),
    FOREIGN KEY (faculty_id) REFERENCES faculty(faculty_id),
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id),
    FOREIGN KEY (year_id)    REFERENCES years(year_id),
    FOREIGN KEY (slot_id)    REFERENCES timetable_slots(slot_id),
    -- Only one ongoing session per room at a time
    UNIQUE KEY uq_live_room (room_id, status, session_date)
);

-- ─────────────────────────────────────────────
-- 8. ROOM RESERVATIONS  (advance booking)
-- ─────────────────────────────────────────────
CREATE TABLE reservations (
    reservation_id  INT AUTO_INCREMENT PRIMARY KEY,
    room_id         INT NOT NULL,
    faculty_id      INT NOT NULL,
    reservation_date DATE NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    purpose         VARCHAR(255),
    status          ENUM('pending','approved','rejected','cancelled') DEFAULT 'pending',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    approved_by     INT NULL COMMENT 'faculty_id of HOD/admin who approved',
    FOREIGN KEY (room_id)    REFERENCES classrooms(room_id),
    FOREIGN KEY (faculty_id) REFERENCES faculty(faculty_id),
    -- No overlapping reservations for same room
    UNIQUE KEY uq_reservation (room_id, reservation_date, start_time)
);

-- ─────────────────────────────────────────────
-- 9. AUDIT LOG
-- ─────────────────────────────────────────────
CREATE TABLE audit_log (
    log_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    action_type   VARCHAR(50)  NOT NULL,
    table_name    VARCHAR(50)  NOT NULL,
    record_id     INT          NOT NULL,
    performed_by  INT          NULL COMMENT 'faculty_id',
    action_detail TEXT,
    action_time   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
--  TRIGGERS
-- ============================================================

DELIMITER $$

-- Prevent double-booking via live_sessions
CREATE TRIGGER trg_prevent_double_booking
BEFORE INSERT ON live_sessions
FOR EACH ROW
BEGIN
    DECLARE cnt INT;
    SELECT COUNT(*) INTO cnt
    FROM live_sessions
    WHERE room_id = NEW.room_id
      AND status  = 'ongoing'
      AND session_date = NEW.session_date;
    IF cnt > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Room is already in use. Cannot start a new session.';
    END IF;
END$$

-- Auto log check-in
CREATE TRIGGER trg_log_checkin
AFTER INSERT ON live_sessions
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (action_type, table_name, record_id, performed_by, action_detail)
    VALUES ('CHECK_IN', 'live_sessions', NEW.session_id, NEW.faculty_id,
            CONCAT('Faculty checked into room for subject_id=', NEW.subject_id));
END$$

-- Auto log check-out
CREATE TRIGGER trg_log_checkout
AFTER UPDATE ON live_sessions
FOR EACH ROW
BEGIN
    IF OLD.status = 'ongoing' AND NEW.status = 'completed' THEN
        INSERT INTO audit_log (action_type, table_name, record_id, performed_by, action_detail)
        VALUES ('CHECK_OUT', 'live_sessions', NEW.session_id, NEW.faculty_id,
                CONCAT('Session ended at ', NEW.check_out_time));
    END IF;
END$$

DELIMITER ;

-- ============================================================
--  VIEWS
-- ============================================================

-- Live Dashboard View
CREATE OR REPLACE VIEW vw_live_dashboard AS
SELECT
    ls.session_id,
    c.room_code,
    c.building,
    c.room_type,
    f.full_name        AS faculty_name,
    f.designation,
    s.subject_name,
    s.subject_code,
    d.dept_name,
    CONCAT('Year ', y.year_number, ' Div ', y.division) AS class_info,
    ls.check_in_time,
    ls.status,
    TIMESTAMPDIFF(MINUTE, ls.check_in_time, NOW()) AS minutes_elapsed
FROM live_sessions ls
JOIN classrooms c  ON ls.room_id    = c.room_id
JOIN faculty f     ON ls.faculty_id = f.faculty_id
JOIN subjects s    ON ls.subject_id = s.subject_id
JOIN years y       ON ls.year_id    = y.year_id
JOIN departments d ON y.dept_id     = d.dept_id
WHERE ls.status = 'ongoing';

-- Available Rooms View
CREATE OR REPLACE VIEW vw_available_rooms AS
SELECT
    c.room_id,
    c.room_code,
    c.building,
    c.floor_number,
    c.room_type,
    c.seating_cap,
    c.has_projector,
    c.has_ac
FROM classrooms c
WHERE c.is_active = 1
  AND c.room_id NOT IN (
      SELECT room_id FROM live_sessions
      WHERE status = 'ongoing' AND session_date = CURDATE()
  );

-- Today's Timetable View
CREATE OR REPLACE VIEW vw_today_timetable AS
SELECT
    ts.slot_id,
    c.room_code,
    f.full_name   AS faculty_name,
    s.subject_name,
    d.dept_name,
    CONCAT('Year ', y.year_number, ' Div ', y.division) AS class_info,
    ts.start_time,
    ts.end_time,
    ts.day_of_week
FROM timetable_slots ts
JOIN classrooms c  ON ts.room_id    = c.room_id
JOIN faculty f     ON ts.faculty_id = f.faculty_id
JOIN subjects s    ON ts.subject_id = s.subject_id
JOIN years y       ON ts.year_id    = y.year_id
JOIN departments d ON y.dept_id     = d.dept_id
WHERE ts.day_of_week = DAYNAME(CURDATE())
  AND ts.academic_year = '2024-25'
ORDER BY ts.start_time;

-- ============================================================
--  STORED PROCEDURES
-- ============================================================

DELIMITER $$

-- Check-in Procedure
CREATE PROCEDURE sp_faculty_checkin(
    IN p_room_id    INT,
    IN p_faculty_id INT,
    IN p_subject_id INT,
    IN p_year_id    INT,
    IN p_slot_id    INT,
    IN p_notes      TEXT,
    OUT p_result    VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 p_result = MESSAGE_TEXT;
        ROLLBACK;
    END;

    START TRANSACTION;
    INSERT INTO live_sessions
        (room_id, faculty_id, subject_id, year_id, slot_id, session_date, notes)
    VALUES
        (p_room_id, p_faculty_id, p_subject_id, p_year_id, p_slot_id, CURDATE(), p_notes);
    SET p_result = 'SUCCESS';
    COMMIT;
END$$

-- Check-out Procedure
CREATE PROCEDURE sp_faculty_checkout(
    IN p_session_id INT,
    OUT p_result    VARCHAR(255)
)
BEGIN
    UPDATE live_sessions
    SET status = 'completed', check_out_time = NOW()
    WHERE session_id = p_session_id AND status = 'ongoing';

    IF ROW_COUNT() = 0 THEN
        SET p_result = 'Session not found or already ended';
    ELSE
        SET p_result = 'SUCCESS';
    END IF;
END$$

-- Reserve Room Procedure
CREATE PROCEDURE sp_reserve_room(
    IN p_room_id    INT,
    IN p_faculty_id INT,
    IN p_date       DATE,
    IN p_start      TIME,
    IN p_end        TIME,
    IN p_purpose    VARCHAR(255),
    OUT p_result    VARCHAR(255)
)
BEGIN
    DECLARE conflict_cnt INT;

    -- Check for conflicts in timetable
    SELECT COUNT(*) INTO conflict_cnt
    FROM timetable_slots
    WHERE room_id = p_room_id
      AND day_of_week = DAYNAME(p_date)
      AND NOT (end_time <= p_start OR start_time >= p_end);

    IF conflict_cnt > 0 THEN
        SET p_result = 'CONFLICT: Room is scheduled in timetable during this time';
    ELSE
        INSERT INTO reservations (room_id, faculty_id, reservation_date, start_time, end_time, purpose)
        VALUES (p_room_id, p_faculty_id, p_date, p_start, p_end, p_purpose);
        SET p_result = 'SUCCESS';
    END IF;
END$$

DELIMITER ;

-- ============================================================
--  SAMPLE DATA
-- ============================================================

INSERT INTO departments (dept_name, dept_code, hod_name) VALUES
('Information Technology',  'IT',  'Dr. Ramesh Kulkarni'),
('Computer Science',        'CS',  'Dr. Priya Nair'),
('Electronics',             'ELEX','Dr. Suresh Patil'),
('Mechanical Engineering',  'MECH','Dr. Anita Desai');

INSERT INTO years (dept_id, year_number, division, total_students) VALUES
(1,1,'A',65),(1,2,'A',60),(1,2,'B',58),(1,3,'A',55),(1,4,'A',50),
(2,1,'A',70),(2,2,'A',65),(2,3,'A',60),
(3,1,'A',55),(3,2,'A',50),
(4,1,'A',60),(4,2,'A',55);

INSERT INTO classrooms (room_code, building, floor_number, room_type, seating_cap, has_projector, has_ac) VALUES
('B801','B-Block',8,'Classroom',65,1,0),
('B811','B-Block',8,'Classroom',60,1,0),
('B812','B-Block',8,'Classroom',60,1,1),
('B901','B-Block',9,'Classroom',70,1,0),
('LAB101','A-Block',1,'Lab',40,1,1),
('LAB201','A-Block',2,'Lab',40,1,1),
('SEMHALL','C-Block',0,'Seminar Hall',120,1,1),
('A301','A-Block',3,'Classroom',65,1,0);

INSERT INTO faculty (dept_id, full_name, employee_code, email, designation) VALUES
(1,'Mrs. Jyoti Sharma',    'EMP001','jyoti.sharma@college.edu',  'Assistant Professor'),
(1,'Mr. Rajesh Mehta',     'EMP002','rajesh.mehta@college.edu',  'Associate Professor'),
(2,'Mrs. Sunita Patil',    'EMP003','sunita.patil@college.edu',  'Assistant Professor'),
(2,'Mr. Aakash Verma',     'EMP004','aakash.verma@college.edu',  'Lecturer'),
(3,'Dr. Kavita Joshi',     'EMP005','kavita.joshi@college.edu',  'Professor'),
(1,'Mr. Nikhil Bhosale',   'EMP006','nikhil.bhosale@college.edu','Assistant Professor'),
(4,'Mrs. Pooja Rane',      'EMP007','pooja.rane@college.edu',    'Assistant Professor');

INSERT INTO subjects (dept_id, year_number, subject_name, subject_code, credits) VALUES
(1,2,'Processor Architecture',  'IT201',4),
(1,2,'Data Structures',         'IT202',4),
(1,3,'Operating Systems',       'IT301',4),
(1,3,'Database Management',     'IT302',4),
(2,2,'Computer Networks',       'CS201',4),
(2,3,'Artificial Intelligence', 'CS301',4),
(3,2,'Digital Electronics',     'EL201',4),
(1,1,'Programming Fundamentals','IT101',4),
(1,4,'Cloud Computing',         'IT401',4);

INSERT INTO timetable_slots (room_id,faculty_id,subject_id,year_id,day_of_week,start_time,end_time,semester,academic_year) VALUES
(2,1,1,2, 'Monday',   '09:00:00','10:00:00',4,'2024-25'),
(3,2,2,2, 'Monday',   '09:00:00','10:00:00',4,'2024-25'),
(1,3,5,7, 'Monday',   '10:00:00','11:00:00',4,'2024-25'),
(2,1,1,2, 'Wednesday','09:00:00','10:00:00',4,'2024-25'),
(4,5,7,10,'Tuesday',  '11:00:00','12:00:00',4,'2024-25'),
(2,6,8,1, 'Thursday', '08:00:00','09:00:00',4,'2024-25');
