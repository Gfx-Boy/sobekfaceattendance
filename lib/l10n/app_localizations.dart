import 'package:flutter/widgets.dart';

class S {
  static Locale _locale = const Locale('en');
  static bool get isArabic => _locale.languageCode == 'ar';

  static void setLocale(Locale locale) {
    _locale = locale;
  }

  static Locale get locale => _locale;

  // ── Helper ──
  static String _t(String en, String ar) => isArabic ? ar : en;

  // ── Common ──
  static String get appName => _t('Sobek', 'سوبك');
  static String get cancel => _t('Cancel', 'إلغاء');
  static String get save => _t('Save', 'حفظ');
  static String get submit => _t('Submit', 'إرسال');
  static String get error => _t('Error', 'خطأ');
  static String get ok => _t('OK', 'موافق');
  static String get required => _t('Required', 'مطلوب');
  static String get email => _t('Email', 'البريد الإلكتروني');
  static String get phone => _t('Phone', 'الهاتف');
  static String get address => _t('Address', 'العنوان');
  static String get department => _t('Department', 'القسم');
  static String get branch => _t('Branch', 'الفرع');
  static String get position => _t('Position', 'المنصب');
  static String get title => _t('Title', 'العنوان');
  static String get description => _t('Description', 'الوصف');
  static String get date => _t('Date', 'التاريخ');
  static String get start => _t('Start', 'بداية');
  static String get end => _t('End', 'نهاية');
  static String get other => _t('Other', 'أخرى');
  static String get password => _t('Password', 'كلمة المرور');

  // ── Login ──
  static String get loginTitle => _t('Log in to your account', 'تسجيل الدخول إلى حسابك');
  static String get emailAddress => _t('Email Address', 'البريد الإلكتروني');
  static String get enterWorkEmail => _t('Enter your work email', 'أدخل بريدك الإلكتروني');
  static String get pleaseEnterEmail => _t('Please enter your email', 'يرجى إدخال بريدك الإلكتروني');
  static String get pleaseEnterValidEmail => _t('Please enter a valid email', 'يرجى إدخال بريد إلكتروني صالح');
  static String get enterPassword => _t('Enter your password', 'أدخل كلمة المرور');
  static String get logIn => _t('Log In', 'تسجيل الدخول');
  static String get loginErrorGeneric => _t('Something went wrong. Please try again later.', 'حدث خطأ ما. يرجى المحاولة لاحقاً.');
  static String get loginErrorNoInternet => _t('No internet connection. Please try again.', 'لا يوجد اتصال بالإنترنت. يرجى المحاولة مرة أخرى.');
  static String get loginErrorInvalidCreds => _t('Invalid credentials. Please try again or contact your administrator.', 'بيانات الاعتماد غير صالحة. يرجى المحاولة مرة أخرى أو الاتصال بالمسؤول.');
  static String get loginErrorContactAdmin => _t('Check with your administrator or request an account.', 'تواصل مع المسؤول أو اطلب إنشاء حساب.');

  // ── Home ──
  static String get welcomeBack => _t('Welcome back,', 'مرحباً بعودتك،');
  static String get employee => _t('Employee', 'موظف');
  static String get quickActions => _t('Quick Actions', 'إجراءات سريعة');
  static String get manageEmployees => _t('Manage Employees', 'إدارة الموظفين');
  static String get attendanceReports => _t('Attendance Reports', 'تقارير الحضور');
  static String get manageRequests => _t('Manage Requests', 'إدارة الطلبات');
  static String get manageBranches => _t('Manage Branches', 'إدارة الفروع');
  static String get addEmployee => _t('Add Employee', 'إضافة موظف');
  static String get tasks => _t('Tasks', 'المهام');
  static String get appraisals => _t('Appraisals', 'التقييمات');
  static String get payslips => _t('Payslips', 'كشوف الرواتب');
  static String get systemSettings => _t('System Settings', 'إعدادات النظام');
  static String get superAdminDesc => _t('Super Admin — Full system access', 'مسؤول أعلى — صلاحيات كاملة');
  static String get branchAdminDesc => _t('Branch Admin — Branch management', 'مدير فرع — إدارة الفرع');
  static String get hrDesc => _t('HR — Employee & attendance management', 'موارد بشرية — إدارة الموظفين والحضور');
  static String get signIn => _t('Sign In', 'تسجيل الدخول');
  static String get signOut => _t('Sign Out', 'تسجيل الخروج');
  static String get takeBreak => _t('Take Break', 'أخذ استراحة');
  static String get endBreak => _t('End Break', 'إنهاء الاستراحة');
  static String get employeeData => _t('Employee Data', 'بيانات الموظفين');
  static String get attendanceMonitor => _t('Attendance Monitor', 'مراقبة الحضور');
  static String get makeRequest => _t('Make Request', 'تقديم طلب');
  static String get history => _t('History', 'السجل');
  static String get myTasks => _t('My Tasks', 'مهامي');
  static String get myPayslips => _t('My Payslips', 'رواتبي');
  static String get todayStatus => _t("Today's Status", 'حالة اليوم');

  // ── Profile ──
  static String get profile => _t('Profile', 'الملف الشخصي');
  static String get confirmLogout => _t('Confirm Logout', 'تأكيد تسجيل الخروج');
  static String get confirmLogoutMsg => _t('Are you sure you want to log out?', 'هل أنت متأكد أنك تريد تسجيل الخروج؟');
  static String get logout => _t('Logout', 'تسجيل الخروج');
  static String get profileImageUpdated => _t('Profile image updated', 'تم تحديث صورة الملف الشخصي');
  static String get attendanceHistory => _t('Attendance History', 'سجل الحضور');

  // ── Attendance ──
  static String get attendance => _t('Attendance', 'الحضور');
  static List<String> get months => isArabic
      ? ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر']
      : ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  static List<String> get weekDays => isArabic
      ? ['اثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت', 'أحد']
      : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static String get breakLabel => _t('Break', 'استراحة');
  static String get weekend => _t('Weekend', 'عطلة نهاية الأسبوع');
  static String get vacation => _t('Vacation', 'إجازة');
  static String get absent => _t('Absent', 'غائب');
  static String get sick => _t('Sick', 'مريض');
  static String get mission => _t('Mission', 'مهمة');
  static String get holiday => _t('Holiday', 'عطلة');
  static String get attend => _t('Attend', 'حاضر');

  // ── Verification ──
  static String get faceCaptured => _t('Face Captured', 'تم التقاط الوجه');
  static String get locationAcquired => _t('Location Acquired', 'تم تحديد الموقع');
  static String get imageUploaded => _t('Image Uploaded', 'تم رفع الصورة');
  static String get identityVerified => _t('Identity Verified', 'تم التحقق من الهوية');
  static String get type => _t('Type', 'النوع');
  static String get faceMatch => _t('Face Match', 'مطابقة الوجه');
  static String get liveness => _t('Liveness', 'حيوية');
  static String get verified => _t('Verified', 'تم التحقق');
  static String get na => _t('N/A', 'غير متوفر');
  static String get location => _t('Location', 'الموقع');
  static String get time => _t('Time', 'الوقت');
  static String get breakStart => _t('Break Start', 'بداية الاستراحة');
  static String get breakEnd => _t('Break End', 'نهاية الاستراحة');
  static String get tryAgain => _t('Try Again', 'حاول مرة أخرى');
  static String get backToHome => _t('Back to Home', 'العودة للرئيسية');
  static String get openLocationSettings => _t('Open Location Settings', 'فتح إعدادات الموقع');
  static String get openAppSettings => _t('Open App Settings', 'فتح إعدادات التطبيق');
  static String get verificationFailed => _t('Verification failed. Please try again.', 'فشل التحقق. يرجى المحاولة مرة أخرى.');
  static String get errorTimeout => _t('The request timed out. Please check your internet connection and try again.', 'انتهت مهلة الطلب. يرجى التحقق من اتصالك بالإنترنت والمحاولة مرة أخرى.');
  static String get errorNoInternet => _t('No internet connection. Please check your network and try again.', 'لا يوجد اتصال بالإنترنت. يرجى التحقق من الشبكة والمحاولة مرة أخرى.');
  static String get errorServer => _t('Something went wrong on the server. Please try again later.', 'حدث خطأ في الخادم. يرجى المحاولة لاحقاً.');
  static String get errorFaceNotRecognized => _t('Face not recognized. Please ensure good lighting and try again.', 'لم يتم التعرف على الوجه. يرجى التأكد من الإضاءة الجيدة والمحاولة مرة أخرى.');
  static String get errorNoFace => _t('No face detected in the image. Please position your face clearly and try again.', 'لم يتم اكتشاف وجه في الصورة. يرجى وضع وجهك بوضوح والمحاولة مرة أخرى.');
  static String get errorGeofence => _t('You are outside the allowed area. Please move closer to your work location.', 'أنت خارج المنطقة المسموح بها. يرجى الاقتراب من موقع عملك.');

  // ── Requests ──
  static String get newRequest => _t('New Request', 'طلب جديد');
  static String get category => _t('Category', 'الفئة');
  static String get hrRequest => _t('HR Request', 'طلب موارد بشرية');
  static String get itRequest => _t('IT Request', 'طلب تقنية معلومات');
  static String get requestType => _t('Request Type', 'نوع الطلب');
  static String get leave => _t('Leave', 'إجازة');
  static String get leavePermission => _t('Leave Permission', 'إذن مغادرة');
  static String get permission => _t('Permission', 'إذن');
  static String get businessMission => _t('Business Mission', 'مهمة عمل');
  static String get emailUserAccount => _t('Email & User Account', 'بريد إلكتروني وحساب مستخدم');
  static String get accessRight => _t('Access Right', 'حق الوصول');
  static String get equipment => _t('Equipment', 'معدات');
  static String get applications => _t('Applications', 'تطبيقات');
  static String get submitRequest => _t('Submit Request', 'تقديم الطلب');
  static String get startDate => _t('Start Date *', 'تاريخ البداية *');
  static String get endDate => _t('End Date *', 'تاريخ النهاية *');
  static String get duration => _t('Duration *', 'المدة *');
  static String get twoHours => _t('2 Hours', 'ساعتان');
  static String get fourHours => _t('4 Hours', '4 ساعات');
  static String get permissionTime => _t('Permission Time', 'وقت الإذن');
  static String get fromDate => _t('From Date *', 'من تاريخ *');
  static String get toDate => _t('To Date *', 'إلى تاريخ *');
  static String get requiredAction => _t('Required Action *', 'الإجراء المطلوب *');
  static String get leaveReason => _t('Leave Reason *', 'سبب الإجازة *');
  static String get sickLeave => _t('Sick Leave', 'إجازة مرضية');
  static String get personal => _t('Personal', 'شخصي');
  static String get familyEmergency => _t('Family Emergency', 'طوارئ عائلية');
  static String get bereavement => _t('Bereavement', 'وفاة');
  static String get applicationType => _t('Application Type *', 'نوع التطبيق *');
  static String get sales => _t('Sales', 'مبيعات');
  static String get accountant => _t('Accountant', 'محاسب');
  static String get warehouse => _t('Warehouse', 'مستودع');
  static String get equipmentType => _t('Equipment Type *', 'نوع المعدات *');
  static String get laptop => _t('Laptop', 'حاسب محمول');
  static String get usb => _t('USB', 'USB');
  static String get printer => _t('Printer', 'طابعة');
  static String get phoneNumber => _t('Phone Number', 'رقم الهاتف');
  static String get requestSubmitted => _t('Request submitted', 'تم تقديم الطلب');
  static String get selectDate => _t('Select date', 'اختر التاريخ');
  static String get selectTime => _t('Select time', 'اختر الوقت');
  static String get vacationDatesRequired => _t('Start date and end date are required for vacation', 'تاريخ البداية والنهاية مطلوبان للإجازة');
  static String get selectPermissionDuration => _t('Please select permission duration', 'يرجى اختيار مدة الإذن');
  static String get selectLeaveReason => _t('Please select a leave reason', 'يرجى اختيار سبب الإجازة');
  static String get missionDatesRequired => _t('From and To dates are required for business mission', 'تاريخ البداية والنهاية مطلوبان للمهمة');

  // ── Settings ──
  static String get timezone => _t('Timezone', 'المنطقة الزمنية');
  static String get selectTimezone => _t('Select Timezone', 'اختر المنطقة الزمنية');
  static String get workingHours => _t('Working Hours', 'ساعات العمل');
  static String get breakSettings => _t('Break Settings', 'إعدادات الاستراحة');
  static String get allowedBreakDuration => _t('Allowed break duration per day', 'مدة الاستراحة المسموح بها يومياً');
  static String get settingsSaved => _t('Settings saved', 'تم حفظ الإعدادات');

  // ── Language ──
  static String get language => _t('Language', 'اللغة');
  static String get english => _t('English', 'الإنجليزية');
  static String get arabic => _t('العربية', 'العربية');

  // ── Employees ──
  static String get addEmployeeTitle => _t('Add Employee', 'إضافة موظف');
  static String get editEmployeeTitle => _t('Edit Employee', 'تعديل بيانات الموظف');
  static String get employees => _t('Employees', 'الموظفون');
  static String get selectBranch => _t('Select Branch', 'اختر الفرع');
  static String get fullName => _t('Full Name', 'الاسم الكامل');
  static String get role => _t('Role', 'الدور');
  static String get employeeTypeLabel => _t('Employee Type', 'نوع الموظف');
  static String get referenceImage => _t('Reference Face Image', 'صورة الوجه المرجعية');
  static String get captureImage => _t('Capture Image', 'التقاط صورة');
  static String get retake => _t('Retake', 'إعادة التقاط');
  static String get enableGeofence => _t('Enable Geofence', 'تفعيل السياج الجغرافي');
  static String get workLocation => _t('Work Location', 'موقع العمل');
  static String get pickLocation => _t('Pick Work Location', 'اختيار موقع العمل');
  static String get latitude => _t('Latitude', 'خط العرض');
  static String get longitude => _t('Longitude', 'خط الطول');
  static String get radiusMeters => _t('Radius (meters)', 'النطاق (بالأمتار)');
  static String get searchEmployees => _t('Search employees...', 'ابحث عن موظفين...');
  static String get noEmployeesFound => _t('No employees found', 'لم يتم العثور على موظفين');
  static String get deleteEmployee => _t('Delete Employee', 'حذف الموظف');
  static String get employeeDeleted => _t('Employee deleted', 'تم حذف الموظف');
  static String get employeeAdded => _t('Employee added successfully', 'تمت إضافة الموظف بنجاح');
  static String get employeeUpdated => _t('Employee updated', 'تم تحديث بيانات الموظف');
  static String get holdAccount => _t('Hold Account', 'تعليق الحساب');
  static String get unholdAccount => _t('Unhold Account', 'إلغاء تعليق الحساب');
  static String get onHold => _t('ON HOLD', 'معلق');
  static String get accountHeld => _t('Account held', 'تم تعليق الحساب');
  static String get accountUnheld => _t('Account unheld', 'تم إلغاء تعليق الحساب');

  // ── Branches ──
  static String get branches => _t('Branches', 'الفروع');
  static String get addBranch => _t('Add Branch', 'إضافة فرع');
  static String get editBranch => _t('Edit Branch', 'تعديل الفرع');
  static String get branchName => _t('Branch Name', 'اسم الفرع');
  static String get validityStart => _t('Validity Start', 'بداية الصلاحية');
  static String get validityEnd => _t('Validity End', 'نهاية الصلاحية');
  static String get startTime => _t('Start Time', 'وقت البداية');
  static String get endTime => _t('End Time', 'وقت النهاية');
  static String get breakDuration => _t('Break Duration', 'مدة الاستراحة');
  static String get minutes => _t('minutes', 'دقيقة');
  static String get workingDays => _t('Working Days', 'أيام العمل');
  static String get noBranchesFound => _t('No branches found', 'لم يتم العثور على فروع');
  static String get branchCreated => _t('Branch created', 'تم إنشاء الفرع');
  static String get branchUpdated => _t('Branch updated', 'تم تحديث الفرع');
  static String get branchDeleted => _t('Branch deleted', 'تم حذف الفرع');
  static String get deleteBranch => _t('Delete Branch', 'حذف الفرع');
  static String get statusWorking => _t('Working', 'يعمل');
  static String get statusOnHold => _t('On Hold', 'معلق');
  static String get statusClosed => _t('Closed', 'مغلق');

  // ── Tasks ──
  static String get createTask => _t('Create Task', 'إنشاء مهمة');
  static String get taskTitle => _t('Task Title', 'عنوان المهمة');
  static String get assignTo => _t('Assign To', 'إسناد إلى');
  static String get selectEmployee => _t('Select Employee', 'اختر الموظف');
  static String get dueDate => _t('Due Date', 'تاريخ الاستحقاق');
  static String get taskCreated => _t('Task created', 'تم إنشاء المهمة');
  static String get toDo => _t('To Do', 'للتنفيذ');
  static String get inProgress => _t('In Progress', 'قيد التنفيذ');
  static String get done => _t('Done', 'منجز');
  static String get noTasks => _t('No tasks', 'لا توجد مهام');

  // ── Appraisals ──
  static String get performanceEvaluations => _t('Performance Evaluations', 'تقييمات الأداء');
  static String get newEvaluation => _t('New Evaluation', 'تقييم جديد');
  static String get period => _t('Period', 'الفترة');
  static String get scores => _t('Scores', 'الدرجات');
  static String get comments => _t('Comments', 'التعليقات');
  static String get noEvaluations => _t('No evaluations yet', 'لا توجد تقييمات بعد');

  // ── Payslips ──
  static String get createPayslip => _t('Create Payslip', 'إنشاء كشف راتب');
  static String get basicSalary => _t('Basic Salary', 'الراتب الأساسي');
  static String get bonuses => _t('Bonuses', 'المكافآت');
  static String get overtimePay => _t('Overtime Pay', 'أجر العمل الإضافي');
  static String get deductions => _t('Deductions', 'الخصومات');
  static String get netSalary => _t('Net Salary', 'صافي الراتب');
  static String get notes => _t('Notes', 'ملاحظات');
  static String get payslipCreated => _t('Payslip created', 'تم إنشاء كشف الراتب');
  static String get downloadPdf => _t('Download PDF', 'تحميل PDF');
  static String get noPayslips => _t('No payslips', 'لا توجد كشوف رواتب');
  static String get salaryBreakdown => _t('Salary Breakdown', 'تفاصيل الراتب');

  // ── Dashboard ──
  static String get adminDashboard => _t('Admin Dashboard', 'لوحة التحكم');
  static String get totalAttendance => _t('Total Attendance', 'إجمالي الحضور');
  static String get pendingRequests => _t('Pending Requests', 'الطلبات المعلقة');
  static String get activeTasks => _t('Active Tasks', 'المهام النشطة');
  static String get totalRequests => _t('Total Requests', 'إجمالي الطلبات');

  // ── Notifications ──
  static String get notifications => _t('Notifications', 'الإشعارات');
  static String get noNotifications => _t('No notifications at this time', 'لا توجد إشعارات حالياً');
  static String get justNow => _t('Just now', 'الآن');

  // ── Reports ──
  static String get reports => _t('Reports', 'التقارير');

  // ── Register ──
  static String get register => _t('Register', 'تسجيل');

  // ── Common Actions ──
  static String get edit => _t('Edit', 'تعديل');
  static String get delete => _t('Delete', 'حذف');
  static String get confirm => _t('Confirm', 'تأكيد');
  static String get approve => _t('Approve', 'موافقة');
  static String get reject => _t('Reject', 'رفض');
  static String get create => _t('Create', 'إنشاء');
  static String get add => _t('Add', 'إضافة');
  static String get status => _t('Status', 'الحالة');
  static String get name => _t('Name', 'الاسم');
  static String get proceed => _t('Proceed', 'متابعة');
  static String get refresh => _t('Refresh', 'تحديث');
  static String get loading => _t('Loading...', 'جاري التحميل...');
  static String get noData => _t('No data', 'لا توجد بيانات');
  static String get captureReferenceImage => _t('Please capture reference face image', 'يرجى التقاط صورة الوجه المرجعية');
  static String get selectEmployeeError => _t('Please select an employee', 'يرجى اختيار موظف');
  static String get titleRequired => _t('Title is required', 'العنوان مطلوب');
  static String get descriptionRequired => _t('Description is required', 'الوصف مطلوب');
  static String get cannotBeUndone => _t('This cannot be undone.', 'لا يمكن التراجع عن هذا.');

  // ── Theme ──
  static String get theme => _t('Theme', 'المظهر');
  static String get light => _t('Light', 'فاتح');
  static String get dark => _t('Dark', 'داكن');
  static String get systemDefault => _t('System', 'النظام');
  static String get darkMode => _t('Dark Mode', 'الوضع الداكن');
  static String get lightMode => _t('Light Mode', 'الوضع الفاتح');

  // ── Home / Status ──
  static String get notSignedInYet => _t('Not signed in yet', 'لم يتم تسجيل الدخول بعد');
  static String get onBreak => _t('On Break', 'في استراحة');
  static String get signedOutStatus => _t('Signed out', 'تم تسجيل الخروج');
  static String get signedInWorking => _t('Signed in — Working', 'مسجل — يعمل');
  static String get tapSignIn => _t('Tap Sign In to mark attendance', 'اضغط تسجيل الدخول لتسجيل الحضور');
  static String get noBreaksTaken => _t('No breaks taken', 'لم يتم أخذ استراحات');
  static String get onlineReady => _t('Online — Ready to mark attendance', 'متصل — جاهز لتسجيل الحضور');

  // ── Employee Data ──
  static String get employeeDataLabel => _t('Employee Data', 'بيانات الموظفين');
  static String get attendanceMonitorLabel => _t('Attendance Monitor', 'مراقبة الحضور');

  // ── Request types ──
  static String get myRequests => _t('My Requests', 'طلباتي');
  static String get viewRequests => _t('View Requests', 'عرض الطلبات');
  static String get pending => _t('Pending', 'قيد الانتظار');
  static String get approved => _t('Approved', 'مقبول');
  static String get rejected => _t('Rejected', 'مرفوض');
  static String get requestDate => _t('Request Date', 'تاريخ الطلب');
  static String get allFieldsRequired => _t('All fields are required', 'جميع الحقول مطلوبة');

  // ── Tasks extra ──
  static String get assignedBy => _t('Assigned By', 'مسند من');
  static String get deadline => _t('Deadline', 'الموعد النهائي');
  static String get attachFile => _t('Attach File', 'إرفاق ملف');
  static String get addComment => _t('Add Comment', 'إضافة تعليق');
  static String get taskFrom => _t('Task From', 'مهمة من');
  static String get createdAt => _t('Created At', 'أنشئت في');
  static String get completed => _t('Completed', 'مكتمل');
  static String get failed => _t('Failed', 'فاشل');
  static String get assignedTasks => _t('Assigned Tasks', 'المهام المسندة');

  // ── Appraisal extra ──
  static String get startAppraisal => _t('Start Appraisal', 'بدء التقييم');
  static String get appraisalDuration => _t('Duration', 'المدة');
  static String get evaluate => _t('Evaluate', 'تقييم');
  static String get branchAdminWeight => _t('Branch Admin Weight', 'وزن مدير الفرع');
  static String get hrWeight => _t('HR Weight', 'وزن الموارد البشرية');
  static String get appraisalResults => _t('Appraisal Results', 'نتائج التقييم');

  // ── Branch extra ──
  static String get weekendDays => _t('Weekend Days', 'أيام العطلة');
  static String get deductionLate => _t('Late Sign-in Deduction', 'خصم التأخير');
  static String get deductionEarlyOut => _t('Early Sign-out Deduction', 'خصم الخروج المبكر');
  static String get deductionAbsent => _t('Absent Deduction', 'خصم الغياب');
  static String get notWorking => _t('Not Working', 'غير عامل');
  static String get branchNameUnique => _t('Branch name must be unique', 'اسم الفرع يجب أن يكون فريداً');

  // ── Payslip extra ──
  static String get selectMonth => _t('Select Month', 'اختر الشهر');

  // ── Misc ──
  static String get camera => _t('Camera', 'الكاميرا');
  static String get gallery => _t('Gallery', 'المعرض');
  static String get chooseImageSource => _t('Choose Image Source', 'اختر مصدر الصورة');
  static String get phoneRequired => _t('Phone number is required', 'رقم الهاتف مطلوب');
  static String get cannotEditSelf => _t('Cannot modify your own account', 'لا يمكن تعديل حسابك الخاص');
  static String get cannotDeleteSelf => _t('Cannot delete your own account', 'لا يمكن حذف حسابك الخاص');
  static String get branchOnly => _t('You can only manage your branch', 'يمكنك إدارة فرعك فقط');
  static String get selectBranchFirst => _t('Select a branch first', 'اختر فرعاً أولاً');
  static String get noAccess => _t('No access', 'لا توجد صلاحية');

  // ── Day Status / Attendance Extra ──
  static String get dayStatus => _t('Day Status', 'حالة اليوم');

  // ── Manage Payslips Extra ──
  static String get allPayslips => _t('All Payslips', 'كل الرواتب');
  static String get createNew => _t('Create New', 'إنشاء جديد');
  static String get noPayslipsFound => _t('No payslips found', 'لا توجد رواتب');
  static String get notesOptional => _t('Notes (optional)', 'ملاحظات (اختياري)');

  // ── Create Appraisal Extra ──
  static String get qualityOfWork => _t('Quality of Work', 'جودة العمل');
  static String get productivity => _t('Productivity', 'الإنتاجية');
  static String get attendanceLabel => _t('Attendance', 'الحضور');
  static String get teamwork => _t('Teamwork', 'العمل الجماعي');
  static String get initiative => _t('Initiative', 'المبادرة');
  static String get overallScore => _t('Overall Score', 'الدرجة الكلية');
  static String get submitEvaluation => _t('Submit Evaluation', 'تقديم التقييم');
  static String get noEvaluationsYet => _t('No evaluations yet', 'لا توجد تقييمات بعد');
  static String get evaluationSubmitted => _t('Evaluation submitted', 'تم تقديم التقييم');

  // ── Edit Employee Extra ──
  static String get emailCannotChange => _t('Email (cannot change)', 'البريد (لا يمكن تغييره)');
  static String get newPasswordHint => _t('New Password (leave empty to keep)', 'كلمة مرور جديدة (اتركها فارغة للإبقاء)');
  static String get saveChanges => _t('Save Changes', 'حفظ التغييرات');
  static String get locationRestriction => _t('Location Restriction', 'تقييد الموقع');
  static String get pickLocationOnMap => _t('Pick Location on Map', 'اختر الموقع على الخريطة');
  static String get changeLocation => _t('Change Location', 'تغيير الموقع');

  // ── History Extra ──
  static String get noAttendanceRecords => _t('No attendance records yet', 'لا توجد سجلات حضور بعد');
  static String get historyAppearHere => _t('Your attendance history will appear here', 'سيظهر سجل حضورك هنا');

  // ── Reports Extra ──
  static String get noEmployeesInBranch => _t('No employees in this branch', 'لا يوجد موظفون في هذا الفرع');
  static String get noRecordsForDay => _t('No attendance records for this day', 'لا توجد سجلات حضور لهذا اليوم');

  // ── Notifications Extra ──
  static String get noNotificationsDesc => _t('You have no notifications at this time', 'ليس لديك إشعارات في الوقت الحالي');
  static String get searchNotifications => _t('Search notifications...', 'البحث في الإشعارات...');

  // ── Request category headers ──
  static String get itRequests => _t('IT Requests', 'طلبات تقنية المعلومات');
  static String get hrRequests => _t('HR Requests', 'طلبات الموارد البشرية');

  // ── Appraisals extra2 ──
  static String get evaluator => _t('Evaluator', 'المقيّم');

  // ── Tasks extra2 ──
  static String get listView => _t('List view', 'عرض القائمة');
  static String get calendarView => _t('Calendar view', 'عرض التقويم');
  static String get overdue => _t('OVERDUE', 'متأخر');
  static String get startTask => _t('Start', 'بدء');

  // ── Validation extra ──
  static String get invalidEmail => _t('Invalid email', 'بريد إلكتروني غير صالح');
  static String get passwordRequired => _t('Password is required', 'كلمة المرور مطلوبة');

  // ── Profile extra ──
  static String get failedToUploadImage => _t('Failed to upload image', 'فشل رفع الصورة');

  // ── Create Request validation ──
  static String get selectPermissionTime => _t('Please select permission time', 'يرجى اختيار وقت الإذن');
  static String get dateRequiredForLeave => _t('Date is required for leave', 'التاريخ مطلوب للإجازة');
  static String get selectApplicationType => _t('Please select an application type', 'يرجى اختيار نوع التطبيق');
  static String get selectEquipmentType => _t('Please select an equipment type', 'يرجى اختيار نوع المعدات');
  static String get emailRequiredForType => _t('Email is required for this request type', 'البريد الإلكتروني مطلوب لهذا النوع من الطلبات');

  // ── Camera ──
  static String get initializingCamera => _t('Initializing camera...', 'جاري تهيئة الكاميرا...');
  static String get cameraNotAvailable => _t('Camera not available', 'الكاميرا غير متوفرة');
  static String get positionFaceInFrame => _t('Position your face in the frame', 'ضع وجهك في الإطار');
  static String get preview => _t('Preview', 'معاينة');
  static String get somethingWentWrong => _t('Something went wrong', 'حدث خطأ ما');
  static String get goBack => _t('Go Back', 'رجوع');
  static String get usePhoto => _t('Use Photo', 'استخدام الصورة');

  // ── Employee form labels ──
  static String get general => _t('General', 'عام');
  static String get management => _t('Management', 'إدارة');
  static String get itDepartment => _t('IT', 'تقنية المعلومات');
  static String get hrManagerRole => _t('HR Manager', 'مدير الموارد البشرية');
  static String get branchAdminRole => _t('Branch Admin', 'مدير الفرع');
  static String get tapToCaptureFace => _t('Tap to capture face photo', 'اضغط لالتقاط صورة الوجه');
  static String get positionOptional => _t('Position (optional)', 'المنصب (اختياري)');
  static String get referenceImageLabel => _t('Reference Face Image *', 'صورة الوجه المرجعية *');
  static String get locationGeofence => _t('Location Restriction (Geofence)', 'تقييد الموقع (السياج الجغرافي)');
  static String get geofenceDescription => _t('Set the allowed work location. Employee must be within this area to mark attendance.', 'حدد موقع العمل المسموح به. يجب أن يكون الموظف ضمن هذه المنطقة لتسجيل الحضور.');
  static String get geofenceAttendanceNote => _t('Employee must be within this area to mark attendance.', 'يجب أن يكون الموظف ضمن هذه المنطقة لتسجيل الحضور.');
  static String get noBranchesAvailable => _t('No branches available', 'لا توجد فروع متاحة');

  // ── Time ago ──
  static String mAgo(int n) => _t('${n}m ago', 'منذ ${n}د');
  static String hAgo(int n) => _t('${n}h ago', 'منذ ${n}س');
  static String dAgo(int n) => _t('${n}d ago', 'منذ ${n}ي');

  // ── Dynamic strings ──
  static String noStatusRequests(String status) => _t('No $status requests', 'لا توجد طلبات $status');
  static String employeeCountLabel(int n) => _t('$n employees', '$n موظفين');
  static String deleteConfirmMessage(String name) => _t('Delete "$name"? This cannot be undone.', 'حذف "$name"؟ لا يمكن التراجع عن هذا.');
  static String holdConfirmMessage(String name) => _t('Put ${name}\'s account on hold? They will not be able to log in.', 'تعليق حساب $name؟ لن يتمكنوا من تسجيل الدخول.');
  static String unholdConfirmMessage(String name) => _t('Remove ${name}\'s account from hold? They will be able to log in again.', 'إلغاء تعليق حساب $name؟ سيتمكنون من تسجيل الدخول مرة أخرى.');

  // ── Payslips extra2 ──
  static String get paySlipTitle => _t('Sobek — Pay Slip', 'سوبك — كشف الراتب');
  static String get paymentDateLabel => _t('Payment Date', 'تاريخ الدفع');
  static String get paidLabel => _t('Paid', 'مدفوع');
  static String get noteLabel => _t('Note', 'ملاحظة');

  // ── Reports extra ──
  static String get noRecordsForThisDay => _t('No attendance records for this day.', 'لا توجد سجلات حضور لهذا اليوم.');

  // ── Branches extra2 ──
  static String get noBranchesYet => _t('No branches yet', 'لا توجد فروع بعد');

  // ── Sunday-first weekdays (for reports) ──
  static List<String> get weekDaysSun => isArabic
      ? ['أحد', 'اثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت']
      : ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
}
