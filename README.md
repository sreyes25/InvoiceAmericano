# Invoice Americano  
A modern invoicing app built with SwiftUI, Supabase, and Stripe.  
Designed for contractors, small businesses, and first-time digital users.

Version 1.0

---

## 🚀 Overview

Invoice Americano is a simple, fast, and bilingual-friendly invoicing app that helps small business owners create invoices, accept payments, and manage clients with ease.

The app focuses on:

- No subscription fees  
- No paywalls  
- Pass-through transaction fee on payments  
- Simple invoice creation  
- PDF generation  
- Real-time updates  
- Client management  
- Custom branding  
- Clean, approachable UI  

---

## 🛠️ Tech Stack

- **SwiftUI** – user interface  
- **Supabase** – authentication, database, storage, realtime  
- **Stripe** – payment links + processing  
- **PDFKit** – invoice PDF rendering  
- **Postgres** – underlying database via Supabase  

---

## 📐 Architecture Overview

Invoice Americano uses a **feature-first modular architecture**, keeping Core logic (auth, networking, storage) separate from product features (Invoices, Clients, Activity, etc.).  
This structure improves maintainability, scalability, and ease of adding new features.

---

## ✨ Features

- Add, edit, and manage clients  
- Create invoices with multiple items  
- Generate professional PDF invoices  
- Upload and store business logos  
- Real-time invoice activity feed  
- Payment link integration through Stripe  
- Customizable branding and defaults  
- First-time onboarding flow  

---

## 🌐 Backend Responsibilities

**Supabase provides:**
- User authentication  
- Database storage for invoices + clients  
- Realtime updates for activity  
- File uploads (logos)

**Stripe provides:**
- Payment links  
- Payment status tracking  

---

## 🧪 Development Notes

- Stripe is currently in **test mode**  
- Supabase Realtime is active for invoice events  
- PDF rendering uses on-device PDFKit  

---

## 🗺️ Roadmap

Planned enhancements:

- Recurring invoices  
- Automated reminders  
- Full English/Spanish language toggle  
- Contractor ↔ client messaging  
- Contract generation  
- Analytics dashboard  

---

## 🏁 Summary

Invoice Americano is built as a real production-ready iOS app with:

- A scalable modular architecture  
- Real backend integrations  
- Clean separation of features  
- Future-proof design  

This project represents a complete, maintainable, and extensible foundation for ongoing development.
