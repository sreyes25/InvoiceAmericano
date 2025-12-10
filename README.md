# Invoice Americano  
*A modern, bilingual-ready invoicing app built with SwiftUI, Supabase, and Stripe.*

Version **1.0**

---

## 🚀 Overview

**Invoice Americano** is a fast, simple, and accessible invoicing app built for contractors, small businesses, and first-time digital users. The app focuses on:

- Zero subscription fees  
- Zero paywalls  
- Small pass-through transaction fee on payments  
- Easy invoice creation  
- PDF generation  
- Client management  
- Real-time activity tracking  
- Branding customization  
- Clean, contractor-friendly UX  

Built with scalability in mind for future features like analytics, contractor networks, recurring invoices, and more.

---

## 📁 Project Architecture

**Architecture Style:** Feature-First Modular Architecture  
**UI Framework:** SwiftUI  
**Backend:** Supabase (Auth, Database, Storage, Realtime)  
**Payments:** Stripe  
**PDF Rendering:** PDFKit  
**Database:** Postgres via Supabase  

This structure enables:

- Clean separation of concerns  
- Faster debugging  
- Easier onboarding for future developers  
- Scalability for new features  
- Low cognitive load when returning to the project after time away  

---

# 🧱 Top-Level Structure

```
InvoiceAmericano/
├── App/
├── Core/
├── Features/
├── Resources/
└── Config/
```

---

# 🔷 App/

Handles launch logic, lifecycle management, and app-wide configuration.

```
App/
│── InvoiceAmericanoApp.swift
│── AppDelegate.swift
│── LocalNotify.swift
│── Info.plist
│── InvoiceAmericano.entitlements
└── Config.xcconfig
```

---

# 🔷 Core/

Shared infrastructure used across multiple features.

```
Core/
├── Models/
│   ├── Profile.swift
│   ├── ActivityEvent.swift
│   └── ActivityJoined.swift
│
├── Networking/
│   ├── SupabaseManager.swift
│   ├── SupabaseStorageService.swift
│   └── StripeService.swift
│
├── Services/
│   ├── AuthService.swift
│   ├── ProfileService.swift
│   ├── BrandingService.swift
│   └── RealtimeService.swift
│
└── Utils/
    └── (future helpers, extensions, constants)
```

**Core Rules:**  
- Reusable by any feature  
- Contains no SwiftUI views  
- Does not depend on any feature folder  

---

# 🔷 Features/

Each feature contains its own Views, ViewModels, Models, and Services.  
This keeps product logic modular and easy to maintain.

---

## **Auth**
```
Features/Auth/
├── Views/
│   └── AuthView.swift
└── ViewModels/
    └── AuthViewModel.swift
```

---

## **Onboarding**
```
Features/Onboarding/
└── Views/
    └── OnboardingFlow.swift
```

---

## **Account**
```
Features/Account/
└── Views/
    ├── AccountView.swift
    ├── BrandingView.swift
    └── HomeView.swift
```

---

## **Navigation**
```
Features/Navigation/
└── Views/
    └── MainTabView.swift
```

---

## **Clients**
```
Features/Clients/
├── Models/
│   └── Clients.swift
├── Views/
│   ├── ClientListView.swift
│   ├── ClientDetailView.swift
│   ├── NewClientView.swift
│   └── EditClientView.swift
└── Services/
    └── ClientService.swift
```

---

## **Invoices**
```
Features/Invoices/
├── Models/
│   ├── Invoices.swift
│   └── InvoiceDetail.swift
│
├── Views/
│   ├── InvoiceListView.swift
│   ├── NewInvoiceView.swift
│   ├── InvoiceDetailView.swift
│   ├── InvoiceDefaultsView.swift
│   └── InvoiceActivityView.swift
│
└── Services/
    ├── InvoiceService.swift
    ├── InvoicePDFSnapshot.swift
    └── PDFGenerator.swift
```

---

## **Activity**
```
Features/Activity/
├── Views/
│   └── ActivityAllView.swift
└── Services/
    └── ActivityService.swift
```

---

## **SharedComponents (Optional Future Folder)**  
Reusable UI elements such as buttons, inputs, list rows, etc.

```
Features/SharedComponents/
```

---

# 📦 Resources/
```
Resources/
└── Assets.xcassets
```

---

# 🌐 Backend Overview

### Supabase powers:
- User authentication  
- Client + invoice storage  
- Activity feed  
- Real-time updates  
- File storage (logos, attachments)  

### Stripe powers:
- Payment links  
- Tracking invoice payments  

---

# 🧪 Testing Notes
- Real-time updates enabled via Supabase Realtime  
- PDF generation handled by `PDFGenerator.swift` using PDFKit  
- Stripe runs in **test mode** during development  

---

# 🎯 Future Roadmap (Supported by Current Architecture)
- Recurring invoices  
- Automated reminders  
- Contractor/client messaging  
- Tax calculations  
- Multi-language support (EN/ES)  
- Contractor profiles  
- Revenue analytics dashboard  

---

# 🏁 Conclusion

Invoice Americano is built on a robust, scalable, and professional architecture that:

- Keeps features isolated  
- Centralizes core logic  
- Enables clean expansion  
- Reduces debugging complexity  
- Supports long-term maintainability  

This project is structured like a real production application—not a tutorial or prototype.

---

# Optional Add-ons  
*(request if needed)*

- CONTRIBUTING.md  
- CHANGELOG.md  
- Architecture diagram  
- App Store Description  
- Marketing copy  
- Founder’s Letter
