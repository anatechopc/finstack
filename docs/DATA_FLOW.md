# Data Flow Diagrams

## 1. System Overview

```mermaid
flowchart TB
    subgraph Client["Flutter App (Dart)"]
        UI["UI Layer\n(Screens & Widgets)"]
        BLoC["BLoC Layer\n(State Management)"]
        Repo["Repository Layer"]
        Svc["Firebase Services"]
        UI --> BLoC --> Repo --> Svc
    end

    subgraph GoFunctions["Go Cloud Functions (GCP)"]
        HTTP["HTTP Functions"]
        Triggers["Firestore Triggers"]
    end

    subgraph Firebase["Firebase Backend"]
        Auth["Firebase Auth"]
        FS["Cloud Firestore"]
        RTDB["Realtime Database"]
        Storage["Cloud Storage"]
        FCM["Cloud Messaging\n(FCM)"]
    end

    subgraph External["External Services"]
        MSGraph["Microsoft Graph API\n(Email)"]
        TransmitSMS["TransmitSMS API\n(SMS/OTP)"]
    end

    %% Flutter ↔ Firebase
    Svc -->|"Sign in / Sign up"| Auth
    Svc -->|"CRUD documents\n(users, loans, payments, ...)"| FS
    Svc -->|"Stream reports\n& read OTP"| RTDB
    Svc -->|"Upload files\n(requirements, photos, signatures)"| Storage
    Svc -->|"Register FCM token\n& receive push"| FCM

    %% Flutter → Go HTTP
    Svc -->|"requestOtp\nsendEmail"| HTTP

    %% Firestore → Go Triggers
    FS -->|"onCreate / onUpdate\n(loans, payments, reviews,\ncapital, notifications)"| Triggers

    %% Go → Firebase
    HTTP -->|"Store OTP"| RTDB
    Triggers -->|"Create notifications"| FS
    Triggers -->|"Update report summaries"| RTDB
    Triggers -->|"Send push via FCM"| FCM

    %% Go → External
    HTTP -->|"Send email"| MSGraph
    HTTP -->|"Send SMS"| TransmitSMS

    style Client fill:#e3f2fd,stroke:#1565c0,color:#000
    style GoFunctions fill:#fff3e0,stroke:#e65100,color:#000
    style Firebase fill:#e8f5e9,stroke:#2e7d32,color:#000
    style External fill:#fce4ec,stroke:#c62828,color:#000
```

---

## 2. Authentication & User Management

```mermaid
flowchart LR
    subgraph Flutter
        AuthBloc["AuthenticationBloc"]
        UserRepo["UserRepository"]
        AuthRepo["AuthenticationRepository"]
        AuthSvc["AuthenticationService\n(Singleton)"]
    end

    subgraph FirebaseServices
        FBAuth["Firebase Auth"]
        FSUsers["Firestore\nusers/{uid}"]
        FSDevices["Firestore\nusers/{uid}/devices/"]
        OTPStore["RTDB\notp/{userId}"]
    end

    subgraph GoHTTP["Go HTTP Functions"]
        ReqOTP["requestOtp"]
        SendEmail["sendEmail"]
    end

    subgraph External
        Email["Microsoft Graph\n(Email)"]
        SMS["TransmitSMS\n(SMS)"]
    end

    subgraph GoTrigger["Go Triggers"]
        UserCreated["userCreated\nonCreate users/"]
    end

    %% Login flow
    AuthBloc -->|"1. login(email, password)"| AuthRepo
    AuthRepo -->|"2. signInWithEmailAndPassword"| FBAuth
    FBAuth -->|"3. ID token + UID"| AuthRepo
    AuthRepo -->|"4. fetch user doc"| FSUsers
    FSUsers -->|"5. user profile"| AuthSvc

    %% Device registration
    AuthBloc -->|"6. register device"| FSDevices

    %% OTP flow
    AuthBloc -->|"7. requestOtp()"| ReqOTP
    ReqOTP -->|"8a. store OTP (5min TTL)"| OTPStore
    ReqOTP -->|"8b. deliver code"| Email
    ReqOTP -->|"8c. deliver code"| SMS
    AuthBloc -->|"9. verifyOtp()"| OTPStore
    OTPStore -->|"10. OTP record"| AuthBloc
    AuthBloc -->|"11. update verification_status"| FSUsers

    %% User created trigger
    FSUsers -.->|"onCreate"| UserCreated
    UserCreated -->|"welcome email"| SendEmail
    SendEmail -->|"deliver"| Email

    style Flutter fill:#e3f2fd,stroke:#1565c0,color:#000
    style FirebaseServices fill:#e8f5e9,stroke:#2e7d32,color:#000
    style GoHTTP fill:#fff3e0,stroke:#e65100,color:#000
    style GoTrigger fill:#fff3e0,stroke:#e65100,color:#000
    style External fill:#fce4ec,stroke:#c62828,color:#000
```

---

## 3. Loan Lifecycle

```mermaid
flowchart TD
    subgraph Flutter["Flutter App"]
        LoanBloc["LoansBloc"]
        LoanRepo["LoanRepository"]
        SchedRepo["LoanScheduleRepository"]
        CalcSvc["LoanCalculationService"]
        StorageRepo["StorageRepository"]
    end

    subgraph Firestore
        FSLoans["loans/{loanId}"]
        FSSchedules["loan_schedules/"]
        FSViews["user_loan_views/"]
        FSNotif["notifications/"]
    end

    subgraph CloudStorage["Cloud Storage"]
        Files["users/{uid}/loans/{loanId}/\n(requirements, photos)"]
    end

    subgraph RTDB["Realtime Database"]
        Reports["companies/{cid}/\nreport_summary/"]
        LoanProduct["companies/{cid}/\nloans/{loanId}"]
    end

    subgraph GoTriggers["Go Triggers"]
        LoanChanges["loanChanges\nonUpdate loans/"]
    end

    %% Application
    LoanBloc -->|"1. addLoan()"| CalcSvc
    CalcSvc -->|"2. calculate schedules\n(fixed or open term)"| LoanBloc
    LoanBloc -->|"3. upload requirements"| StorageRepo
    StorageRepo -->|"4. store files"| Files
    LoanBloc -->|"5. create loan doc\nstatus: pending"| FSLoans
    LoanBloc -->|"6. create view doc"| FSViews
    LoanBloc -->|"7. write product type"| LoanProduct

    %% Approval
    LoanBloc -->|"8. updateStatus\n→ approved"| FSLoans
    LoanBloc -->|"9. create first schedule"| FSSchedules

    %% Trigger fires
    FSLoans -.->|"onUpdate"| LoanChanges

    %% Trigger actions per status
    LoanChanges -->|"pending:\nnotify borrower,\ncompany, co-makers"| FSNotif
    LoanChanges -->|"approved:\nupdate released amounts"| Reports
    LoanChanges -->|"approved:\nnotify borrower"| FSNotif
    LoanChanges -->|"declined:\nnotify borrower"| FSNotif
    LoanChanges -->|"bad_debt:\nupdate bad debt totals"| Reports
    LoanChanges -->|"completed:\naggregate final totals"| Reports

    style Flutter fill:#e3f2fd,stroke:#1565c0,color:#000
    style Firestore fill:#e8f5e9,stroke:#2e7d32,color:#000
    style CloudStorage fill:#fff9c4,stroke:#f9a825,color:#000
    style RTDB fill:#f3e5f5,stroke:#6a1b9a,color:#000
    style GoTriggers fill:#fff3e0,stroke:#e65100,color:#000
```

### Loan Status State Machine

```mermaid
stateDiagram-v2
    [*] --> pending : Borrower submits application
    pending --> approved : Loan officer approves
    pending --> declined : Loan officer declines
    declined --> [*]

    approved --> payment_submitted : Borrower submits payment
    payment_submitted --> paid_on_time : Confirmed before due date
    payment_submitted --> paid_late : Confirmed after due date

    approved --> not_paid : Due date passed, no payment
    not_paid --> not_paid_overdue : Extended overdue

    paid_on_time --> approved : Next schedule cycle
    paid_late --> approved : Next schedule cycle

    approved --> completed : All schedules paid
    paid_on_time --> completed : Final schedule paid
    paid_late --> completed : Final schedule paid

    not_paid --> bad_debt : Written off
    not_paid_overdue --> bad_debt : Written off
    bad_debt --> [*]
    completed --> [*]
```

---

## 4. Payment Flow

```mermaid
flowchart TD
    subgraph Flutter["Flutter App"]
        PayBloc["PaymentBloc"]
        PayRepo["PaymentRepository"]
        SchedRepo["LoanScheduleRepository"]
        LoanRepo["LoanRepository"]
        PoolRepo["CashPoolRepository"]
        StorageRepo["StorageRepository"]
    end

    subgraph CloudStorage["Cloud Storage"]
        PayFiles["users/{uid}/loans/{loanId}/\ntransaction_photo, signature"]
    end

    subgraph Firestore
        FSPayment["payments/{paymentId}"]
        FSSchedule["loan_schedules/{schedId}"]
        FSLoan["loans/{loanId}"]
        FSPool["cash_pool/{recordId}"]
        FSNotif["notifications/"]
    end

    subgraph RTDB["Realtime Database"]
        Reports["companies/{cid}/\nreport_summary/"]
    end

    subgraph GoTriggers["Go Triggers"]
        PayCreated["paymentCreated\nonCreate payments/"]
        SchedChanges["loanScheduleChanges\nonCreate loan_schedules/"]
    end

    %% Payment submission
    PayBloc -->|"1. makePayment()"| StorageRepo
    StorageRepo -->|"2. upload photo + signature"| PayFiles
    PayBloc -->|"3. create payment doc"| FSPayment
    PayBloc -->|"4. update schedule\n(interest, principal,\noutstanding balance,\nstatus, paid_at)"| FSSchedule
    PayBloc -->|"5. update loan status"| FSLoan
    PayBloc -->|"6. deduct from cash pool"| FSPool

    %% Triggers
    FSPayment -.->|"onCreate"| PayCreated
    FSSchedule -.->|"onCreate"| SchedChanges

    %% paymentCreated actions
    PayCreated -->|"notify admins +\nloan officers"| FSNotif

    %% loanScheduleChanges actions
    SchedChanges -->|"update collections,\ninterest, principal,\ncapital usage"| Reports

    style Flutter fill:#e3f2fd,stroke:#1565c0,color:#000
    style CloudStorage fill:#fff9c4,stroke:#f9a825,color:#000
    style Firestore fill:#e8f5e9,stroke:#2e7d32,color:#000
    style RTDB fill:#f3e5f5,stroke:#6a1b9a,color:#000
    style GoTriggers fill:#fff3e0,stroke:#e65100,color:#000
```

---

## 5. Notification Flow (End-to-End)

```mermaid
flowchart LR
    subgraph Sources["Notification Sources\n(Go Triggers)"]
        T1["loanChanges\n(loan status updates)"]
        T2["paymentCreated\n(new payments)"]
        T3["reviewCreated\n(new reviews)"]
    end

    subgraph Firestore
        FSNotif["notifications/\n{notifId}"]
    end

    subgraph Delivery["Go Trigger: notificationCreated"]
        NotifTrigger["notificationCreated\nonCreate notifications/"]
    end

    subgraph FCMService["Firebase Cloud Messaging"]
        FCM["FCM\nMulticast Send"]
    end

    subgraph DeviceStore["Firestore"]
        Devices["users/{uid}/\ndevices/"]
    end

    subgraph FlutterApp["Flutter App"]
        NotifSvc["NotificationService\n(FCM listener)"]
        NotifRepo["NotificationRepository\n(Firestore stream)"]
        NotifUI["Notification UI\n(badge + list)"]
    end

    %% Creation
    T1 -->|"create notification doc\n(recipient, title, message,\npriority, data)"| FSNotif
    T2 -->|"create notification doc"| FSNotif
    T3 -->|"create notification doc"| FSNotif

    %% Trigger fires
    FSNotif -.->|"onCreate"| NotifTrigger

    %% Push delivery
    NotifTrigger -->|"1. lookup recipient\ndevice tokens"| Devices
    Devices -->|"2. FCM tokens[]"| NotifTrigger
    NotifTrigger -->|"3. sendEachForMulticast\n(Android + iOS config)"| FCM

    %% Client receives
    FCM -->|"4. push notification"| NotifSvc
    NotifSvc -->|"5. display OS notification\n+ handle tap"| NotifUI

    %% In-app stream
    FSNotif -->|"6. real-time stream\n(recipient_id == uid)"| NotifRepo
    NotifRepo -->|"7. update notification list"| NotifUI

    style Sources fill:#fff3e0,stroke:#e65100,color:#000
    style Firestore fill:#e8f5e9,stroke:#2e7d32,color:#000
    style Delivery fill:#fff3e0,stroke:#e65100,color:#000
    style FCMService fill:#ffebee,stroke:#c62828,color:#000
    style DeviceStore fill:#e8f5e9,stroke:#2e7d32,color:#000
    style FlutterApp fill:#e3f2fd,stroke:#1565c0,color:#000
```

---

## 6. Review & Karma Flow

```mermaid
flowchart TD
    subgraph Flutter["Flutter App"]
        LoanBloc["LoansBloc"]
        ReviewRepo["ReviewRepository"]
        CompanyRepo["CompanyRepository"]
        PVRepo["ProductViewRepository"]
    end

    subgraph Firestore
        FSReview["reviews/{reviewId}"]
        FSCompany["companies/{cid}"]
        FSProductView["product_views/{pvId}"]
        FSKarma["karma_transactions/"]
        FSUser["users/{uid}"]
        FSNotif["notifications/"]
    end

    subgraph GoTriggers["Go Triggers"]
        ReviewCreated["reviewCreated\nonCreate reviews/"]
    end

    %% Review submission
    LoanBloc -->|"1. addReview()\nrating + message"| FSReview
    LoanBloc -->|"2. update company\nreview_count += 1\ntotal_rating += rating"| FSCompany
    LoanBloc -->|"3. update product view\nreview_count, rating_avg"| FSProductView

    %% Trigger
    FSReview -.->|"onCreate"| ReviewCreated
    ReviewCreated -->|"4. notify admins +\nreview moderators"| FSNotif

    %% Karma (separate flow)
    LoanBloc -->|"5. create karma\ntransaction"| FSKarma
    LoanBloc -->|"6. update user.karma\n+= earned amount"| FSUser

    style Flutter fill:#e3f2fd,stroke:#1565c0,color:#000
    style Firestore fill:#e8f5e9,stroke:#2e7d32,color:#000
    style GoTriggers fill:#fff3e0,stroke:#e65100,color:#000
```

---

## 7. Capital & Cash Pool Flow

```mermaid
flowchart TD
    subgraph Flutter["Flutter App"]
        CapBloc["CapitalBloc"]
        PoolBloc["CashPoolBloc"]
        CapRepo["CapitalRepository"]
        PoolRepo["CashPoolRepository"]
    end

    subgraph Firestore
        FSCapital["capital/{capitalId}"]
        FSPool["cash_pool/{recordId}"]
    end

    subgraph RTDB["Realtime Database"]
        CapUsage["companies/{cid}/\nreport_summary/\ncapital_usage/"]
        ReportData["companies/{cid}/\nreport_summary/\ndata/{timestamp}"]
    end

    subgraph GoTriggers["Go Triggers"]
        CapCreated["capitalCreated\nonCreate capital/"]
    end

    %% Capital addition
    CapBloc -->|"1. addCapital(amount)"| FSCapital
    FSCapital -.->|"onCreate"| CapCreated
    CapCreated -->|"2. total_capital += amount"| CapUsage
    CapCreated -->|"3. record: type=add_capital"| ReportData

    %% Cash pool operations
    PoolBloc -->|"add_to_pool:\nteller deposits cash"| FSPool
    PoolBloc -->|"acknowledged_payment:\npayment deduction"| FSPool
    PoolBloc -->|"change:\ncash change given"| FSPool
    PoolBloc -->|"savings:\nuser savings"| FSPool

    %% Balance calculation
    FSPool -->|"stream all records\nbalance = deposits\n- acknowledged\n- change - savings"| PoolBloc

    style Flutter fill:#e3f2fd,stroke:#1565c0,color:#000
    style Firestore fill:#e8f5e9,stroke:#2e7d32,color:#000
    style RTDB fill:#f3e5f5,stroke:#6a1b9a,color:#000
    style GoTriggers fill:#fff3e0,stroke:#e65100,color:#000
```

---

## 8. Reports Flow (Real-time Analytics)

```mermaid
flowchart LR
    subgraph GoTriggers["Go Triggers\n(Write to RTDB)"]
        T1["loanChanges\n→ released, bad_debt"]
        T2["loanScheduleChanges\n→ collections, interest,\nprincipal, capital refresh"]
        T3["capitalCreated\n→ add_capital"]
    end

    subgraph RTDB["Realtime Database"]
        subgraph ReportSummary["report_summary/"]
            Sales["sales/\ntotal_amount_released\ntotal_collections\ntotal_interest_payments\ntotal_principal_payments"]
            Products["products/{type}/\ntotal_amount_released\ntotal_collections\ntotal_bad_debts\n..."]
            TotalSummary["total_summary/\nyear → month → week → day\n(time-series aggregates)"]
            CapUsage["capital_usage/\ntotal_capital\ntotal_bad_debts"]
            Data["data/{timestamp}\namount, interest, principal\nproduct_type, data_type\ncapital_id, loan_id"]
        end
    end

    subgraph Flutter["Flutter App"]
        ReportsBloc["ReportsBloc"]
        ReportsRepo["ReportsRepository"]
        RTDBSvc["ReportsRealtimeDB\nService"]
        Dashboard["Admin Dashboard UI"]
    end

    %% Go writes to RTDB
    T1 -->|"update"| Sales
    T1 -->|"update"| Products
    T1 -->|"update"| TotalSummary
    T1 -->|"update"| CapUsage
    T1 -->|"insert"| Data

    T2 -->|"update"| Sales
    T2 -->|"update"| Products
    T2 -->|"update"| TotalSummary
    T2 -->|"update"| CapUsage
    T2 -->|"insert"| Data

    T3 -->|"update"| CapUsage
    T3 -->|"insert"| Data

    %% Flutter reads from RTDB
    Sales -->|"real-time stream"| RTDBSvc
    Products -->|"real-time stream"| RTDBSvc
    TotalSummary -->|"real-time stream"| RTDBSvc
    CapUsage -->|"real-time stream"| RTDBSvc

    RTDBSvc --> ReportsRepo --> ReportsBloc --> Dashboard

    style GoTriggers fill:#fff3e0,stroke:#e65100,color:#000
    style RTDB fill:#f3e5f5,stroke:#6a1b9a,color:#000
    style ReportSummary fill:#f3e5f5,stroke:#6a1b9a,color:#000
    style Flutter fill:#e3f2fd,stroke:#1565c0,color:#000
```

---

## 9. File Storage Flow

```mermaid
flowchart TD
    subgraph Flutter["Flutter App"]
        LoanBloc["LoansBloc"]
        PayBloc["PaymentBloc"]
        UserBloc["UserBloc"]
        StorageRepo["StorageRepository"]
    end

    subgraph CloudStorage["Firebase Cloud Storage"]
        UserFiles["users/{uid}/"]
        LoanFiles["users/{uid}/loans/{loanId}/"]
        ProfileFiles["users/{uid}/profile/"]
    end

    LoanBloc -->|"loan requirements\n(IDs, documents)"| StorageRepo
    PayBloc -->|"transaction photos\n+ signatures"| StorageRepo
    UserBloc -->|"profile photo\n+ valid ID photo"| StorageRepo

    StorageRepo -->|"upload"| LoanFiles
    StorageRepo -->|"upload"| LoanFiles
    StorageRepo -->|"upload"| ProfileFiles

    LoanFiles -->|"download URL\n→ stored in Firestore doc"| StorageRepo
    ProfileFiles -->|"download URL\n→ stored in user doc"| StorageRepo

    style Flutter fill:#e3f2fd,stroke:#1565c0,color:#000
    style CloudStorage fill:#fff9c4,stroke:#f9a825,color:#000
```

---

## 10. Complete Trigger Map

| Go Function | Type | Firestore Event | Reads | Writes |
|-------------|------|-----------------|-------|--------|
| `requestOtp` | HTTP | - | JWT token | RTDB `otp/`, Email/SMS |
| `sendEmail` | HTTP | - | Request body | Microsoft Graph API |
| `userCreated` | Trigger | `onCreate users/{uid}` | New user doc | `sendEmail` (welcome) |
| `loanChanges` | Trigger | `onUpdate loans/{id}` | Loan doc, schedules, company users | RTDB reports, Firestore notifications |
| `paymentCreated` | Trigger | `onCreate payments/{id}` | Payment, loan, company users | Firestore notifications |
| `loanScheduleChanges` | Trigger | `onCreate loan_schedules/{id}` | Schedule doc, loan doc | RTDB reports |
| `reviewCreated` | Trigger | `onCreate reviews/{id}` | Review, company users | Firestore notifications |
| `capitalCreated` | Trigger | `onCreate capital/{id}` | Capital doc | RTDB reports |
| `notificationCreated` | Trigger | `onCreate notifications/{id}` | Notification, user devices | FCM multicast push |

---

## Color Legend

| Color | Represents |
|-------|------------|
| Blue | Flutter App (client-side) |
| Orange | Go Cloud Functions (server-side) |
| Green | Cloud Firestore (document DB) |
| Purple | Realtime Database (analytics/OTP) |
| Yellow | Cloud Storage (files) |
| Red/Pink | External services (Email, SMS, FCM) |
