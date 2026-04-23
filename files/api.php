<?php
// ============================================================
//  api.php — Classroom Management System Backend
//  Place this file in your XAMPP htdocs/classroom/ folder
// ============================================================

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

// ── Database Connection ─────────────────────────────────────
$host = "localhost";
$user = "root";
$pass = "";           // default XAMPP password is empty
$db   = "classroom_mgmt";

$conn = new mysqli($host, $user, $pass, $db);
if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(["error" => "DB connection failed: " . $conn->connect_error]);
    exit;
}
$conn->set_charset("utf8");

// ── Router ─────────────────────────────────────────────────
$action = $_GET['action'] ?? $_POST['action'] ?? '';
$body   = json_decode(file_get_contents("php://input"), true) ?? [];

switch ($action) {

    // ── Seed / Bootstrap ──────────────────────────────────
    case 'init':
        echo json_encode(["status" => "DB ready"]);
        break;

    // ── GET: All Faculty ──────────────────────────────────
    case 'get_faculty':
        $r = $conn->query("SELECT f.*, d.dept_name, d.dept_code FROM faculty f JOIN departments d ON f.dept_id=d.dept_id WHERE f.is_active=1 ORDER BY f.full_name");
        echo json_encode(rows($r));
        break;

    // ── GET: All Rooms ────────────────────────────────────
    case 'get_rooms':
        $r = $conn->query("SELECT * FROM classrooms WHERE is_active=1 ORDER BY room_code");
        echo json_encode(rows($r));
        break;

    // ── GET: Available Rooms ──────────────────────────────
    case 'get_available_rooms':
        $r = $conn->query("SELECT * FROM vw_available_rooms ORDER BY room_code");
        echo json_encode(rows($r));
        break;

    // ── GET: Live Dashboard ───────────────────────────────
    case 'get_live_sessions':
        $r = $conn->query("SELECT * FROM vw_live_dashboard ORDER BY check_in_time DESC");
        echo json_encode(rows($r));
        break;

    // ── GET: All Subjects ─────────────────────────────────
    case 'get_subjects':
        $r = $conn->query("SELECT s.*, d.dept_name FROM subjects s JOIN departments d ON s.dept_id=d.dept_id ORDER BY s.subject_name");
        echo json_encode(rows($r));
        break;

    // ── GET: All Years ────────────────────────────────────
    case 'get_years':
        $r = $conn->query("SELECT y.*, d.dept_name, d.dept_code FROM years y JOIN departments d ON y.dept_id=d.dept_id ORDER BY d.dept_name, y.year_number, y.division");
        echo json_encode(rows($r));
        break;

    // ── GET: Today's Timetable ────────────────────────────
    case 'get_today_timetable':
        $r = $conn->query("SELECT * FROM vw_today_timetable");
        echo json_encode(rows($r));
        break;

    // ── GET: Full Timetable ───────────────────────────────
    case 'get_timetable':
        $roomId    = intval($_GET['room_id'] ?? 0);
        $facultyId = intval($_GET['faculty_id'] ?? 0);
        $where = "WHERE 1=1";
        if ($roomId)    $where .= " AND ts.room_id = $roomId";
        if ($facultyId) $where .= " AND ts.faculty_id = $facultyId";
        $r = $conn->query("
            SELECT ts.*, c.room_code, f.full_name AS faculty_name,
                   s.subject_name, s.subject_code,
                   d.dept_name,
                   CONCAT('Year ',y.year_number,' Div ',y.division) AS class_info
            FROM timetable_slots ts
            JOIN classrooms c  ON ts.room_id    = c.room_id
            JOIN faculty f     ON ts.faculty_id = f.faculty_id
            JOIN subjects s    ON ts.subject_id = s.subject_id
            JOIN years y       ON ts.year_id    = y.year_id
            JOIN departments d ON y.dept_id     = d.dept_id
            $where
            ORDER BY ts.day_of_week, ts.start_time
        ");
        echo json_encode(rows($r));
        break;

    // ── GET: Reservations ─────────────────────────────────
    case 'get_reservations':
        $r = $conn->query("
            SELECT rv.*, c.room_code, f.full_name AS faculty_name
            FROM reservations rv
            JOIN classrooms c ON rv.room_id    = c.room_id
            JOIN faculty f    ON rv.faculty_id = f.faculty_id
            WHERE rv.reservation_date >= CURDATE()
            ORDER BY rv.reservation_date, rv.start_time
        ");
        echo json_encode(rows($r));
        break;

    // ── GET: Audit Log ────────────────────────────────────
    case 'get_audit':
        $r = $conn->query("
            SELECT al.*, f.full_name AS faculty_name
            FROM audit_log al
            LEFT JOIN faculty f ON al.performed_by = f.faculty_id
            ORDER BY al.action_time DESC
            LIMIT 100
        ");
        echo json_encode(rows($r));
        break;

    // ── POST: Faculty Check-In ────────────────────────────
    case 'checkin':
        $roomId    = intval($body['room_id']    ?? 0);
        $facultyId = intval($body['faculty_id'] ?? 0);
        $subjectId = intval($body['subject_id'] ?? 0);
        $yearId    = intval($body['year_id']    ?? 0);
        $notes     = $conn->real_escape_string($body['notes'] ?? '');

        if (!$roomId || !$facultyId || !$subjectId || !$yearId) {
            echo json_encode(["error" => "All fields are required."]); break;
        }

        // Call stored procedure
        $result = '';
        $stmt = $conn->prepare("CALL sp_faculty_checkin(?,?,?,?,NULL,?,@result)");
        $stmt->bind_param("iiiis", $roomId, $facultyId, $subjectId, $yearId, $notes);
        $stmt->execute();
        $stmt->close();

        $r = $conn->query("SELECT @result AS result");
        $row = $r->fetch_assoc();
        $res = $row['result'];

        if ($res === 'SUCCESS') {
            echo json_encode(["success" => true, "message" => "Check-in successful!"]);
        } else {
            echo json_encode(["error" => $res]);
        }
        break;

    // ── POST: Faculty Check-Out ───────────────────────────
    case 'checkout':
        $sessionId = intval($body['session_id'] ?? 0);
        if (!$sessionId) { echo json_encode(["error" => "session_id required"]); break; }

        $result = '';
        $stmt = $conn->prepare("CALL sp_faculty_checkout(?, @result)");
        $stmt->bind_param("i", $sessionId);
        $stmt->execute();
        $stmt->close();

        $r = $conn->query("SELECT @result AS result");
        $row = $r->fetch_assoc();
        $res = $row['result'];

        if ($res === 'SUCCESS') {
            echo json_encode(["success" => true, "message" => "Checked out successfully!"]);
        } else {
            echo json_encode(["error" => $res]);
        }
        break;

    // ── POST: Reserve Room ────────────────────────────────
    case 'reserve':
        $roomId    = intval($body['room_id']    ?? 0);
        $facultyId = intval($body['faculty_id'] ?? 0);
        $date      = $conn->real_escape_string($body['date']    ?? '');
        $start     = $conn->real_escape_string($body['start']   ?? '');
        $end       = $conn->real_escape_string($body['end']     ?? '');
        $purpose   = $conn->real_escape_string($body['purpose'] ?? '');

        if (!$roomId || !$facultyId || !$date || !$start || !$end) {
            echo json_encode(["error" => "All fields are required."]); break;
        }

        $stmt = $conn->prepare("CALL sp_reserve_room(?,?,?,?,?,?,@result)");
        $stmt->bind_param("iissss", $roomId, $facultyId, $date, $start, $end, $purpose);
        $stmt->execute();
        $stmt->close();

        $r = $conn->query("SELECT @result AS result");
        $row = $r->fetch_assoc();
        $res = $row['result'];

        if ($res === 'SUCCESS') {
            echo json_encode(["success" => true, "message" => "Room reserved!"]);
        } else {
            echo json_encode(["error" => $res]);
        }
        break;

    // ── Departments ───────────────────────────────────────
    case 'get_departments':
        $r = $conn->query("SELECT * FROM departments ORDER BY dept_name");
        echo json_encode(rows($r));
        break;

    default:
        echo json_encode(["error" => "Unknown action: $action"]);
}

$conn->close();

// ── Helper ─────────────────────────────────────────────────
function rows($result) {
    if (!$result) return [];
    $data = [];
    while ($row = $result->fetch_assoc()) $data[] = $row;
    return $data;
}
?>
