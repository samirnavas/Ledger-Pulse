# Windows CTS-2010 Cheque Printing Guide (Ludgerpulse ERP)

This document provides technical instructions for configuring physical cheque printers (dot matrix, laser, and passbook/cheque slip printers) with **Ludgerpulse ERP** on Windows desktop.

---

## 1. Statutory Indian CTS-2010 Dimensions

Standard Indian CTS-2010 cheques adhere to strictly defined RBI and NPCI clearing specifications:
* **Cheque Dimensions:** `203 mm x 95 mm` (approx. `8.0 inches x 3.74 inches`)
* **Aspect Ratio:** `2.137`
* **Page Format Point Size:** `575.43 pt x 269.29 pt`

### Critical Exclusion Zones:
* **Bottom MICR Band:** The bottom `19 mm` is strictly reserved for the magnetic ink MICR line (cheque number, 9-digit MICR routing code, account type code, and transaction code). **No text, graphics, or crossing lines are ever printed within this band.**
* **Watermark & UV Fiber Band:** The top-left and central zones must not be obstructed by large dark solid boxes.

---

## 2. Bank Layout Profiles

Ludgerpulse includes pre-calibrated millimeter coordinate profiles for leading Indian banks:
* **State Bank of India (SBI)**
* **HDFC Bank**
* **ICICI Bank**
* **Axis Bank**
* **Punjab National Bank (PNB)**
* **Canara Bank**
* **Bank of Baroda**
* **Standard Indian CTS-2010 (Fallback Profile)**

---

## 3. Printer Calibration & Millimeter Offsets

Different physical printer trays (manual top-feed, center envelope guides, and landscape dot-matrix feeds) can have mechanical paper-feed margins. 

### Fine-Tuning Offsets:
Use the calibration controls in **CTS-2010 Cheque Preview**:
* `X Offset (mm)`: Adjusts horizontal position left (`-X`) or right (`+X`).
* `Y Offset (mm)`: Adjusts vertical position up (`-Y`) or down (`+Y`).
* Use the **Guidelines / Test Border** toggle to print on plain paper and overlay against your blank cheque leaf against a light source.

---

## 4. Security Formatting Standard

* **Payee Name:** Automatically bounded with `*** [Payee Name] ***` to prevent fraudulent prefix/suffix additions.
* **Amount in Words:** Converted to Indian numbering system (`Lakhs & Crores`) with `*** ... Only ***` wrapping.
* **Amount in Figures:** Formatted as `*** ₹ 1,50,000.00 /- ***`.
* **Crossing:** Automatically stamps dual parallel lines with `A/C PAYEE ONLY` rotated -28° on the top-left margin.
