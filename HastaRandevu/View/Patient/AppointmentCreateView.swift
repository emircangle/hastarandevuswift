import SwiftUI

struct AppointmentCreateView: View {
    @Environment(\.presentationMode) var presentationMode

    @State private var selectedClinic: Clinic?
    @State private var clinics: [Clinic] = []
    @State private var selectedDoctorId: Int?
    @State private var selectedDate = Date()
    @State private var selectedTime: String = ""
    @State private var descriptionText = ""

    @State private var doctors: [User] = []
    @State private var groupedTimeSlots: [(hour: String, slots: [String])] = []
    @State private var pastTimes: [String] = []
    @State private var doctorAppointments: [Appointments] = []
    @State private var allAppointments: [Appointments] = []

    @State private var patientId: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveSuccess = false
    @State private var showReplaceAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📅 Randevu Oluştur")
                .font(.largeTitle)
                .bold()

            Picker("Klinik Seçiniz", selection: $selectedClinic) {
                Text("-- Seçiniz --").tag(nil as Clinic?)
                ForEach(clinics) { clinic in
                    Text(clinic.name).tag(clinic as Clinic?)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .onChange(of: selectedClinic) { _ in
                selectedDoctorId = nil
                selectedTime = ""
                fetchDoctors()
                clearFeedback()
            }

            Picker("Doktor Seçiniz", selection: $selectedDoctorId) {
                Text("-- Seçiniz --").tag(nil as Int?)
                ForEach(doctors, id: \.id) {
                    Text("\($0.name) \($0.surname)").tag($0.id as Int?)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .onChange(of: selectedDoctorId) { _ in
                selectedTime = ""
                fetchDoctorAppointments()
                clearFeedback()
            }

            DatePicker("Tarih Seçiniz", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                .onChange(of: selectedDate) { _ in
                    clearFeedback()
                    generateTimeSlots()
                }

            if !groupedTimeSlots.isEmpty {
                Text("Saat Seçiniz")
                ScrollView(.vertical) {
                    ForEach(groupedTimeSlots, id: \.hour) { group in
                        Text("⏰ \(group.hour)").bold()
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(group.slots, id: \.self) { slot in
                                    Button(action: { selectedTime = slot }) {
                                        Text(slot)
                                            .padding()
                                            .background(selectedTime == slot ? Color.blue : Color.gray.opacity(0.3))
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                    .disabled(isSlotDisabled(slot))
                                }
                            }
                        }
                    }
                }
            }

            TextField("Açıklama (Opsiyonel)", text: $descriptionText)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Button("Randevuyu Kaydet") {
                checkAppointmentConditions()
            }
            .disabled(Calendar.current.isDateInWeekend(selectedDate))
            .frame(maxWidth: .infinity)
            .padding()
            .background(Calendar.current.isDateInWeekend(selectedDate) ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)

            if Calendar.current.isDateInWeekend(selectedDate) {
                Text("🚫 Hafta sonu randevu alınamaz.")
                    .foregroundColor(.red)
            }

            if let error = errorMessage {
                Text("❌ \(error)").foregroundColor(.red)
            }

            if saveSuccess {
                Text("✅ Randevu başarıyla oluşturuldu!").foregroundColor(.green)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            fetchCurrentUser()
            fetchClinics()
            _ = TokenUtil.getRoleFromToken()
        }
        .navigationTitle("Randevu Oluştur")
        .alert(isPresented: $showReplaceAlert) {
            Alert(
                title: Text("Aktif Randevu Var"),
                message: Text("Bu klinikte aktif bir randevunuz bulunuyor. Yeni randevu alırsanız eskisi iptal edilecek. Devam edilsin mi?"),
                primaryButton: .default(Text("Evet")) { saveAppointment() },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Yardımcı Fonksiyonlar

    private func fetchClinics() {
        ClinicService.shared.getAllClinics { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    self.clinics = data.filter { $0.isActive }
                case .failure(let error):
                    self.errorMessage = "Klinikler alınamadı: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearFeedback() {
        errorMessage = nil
        saveSuccess = false
    }

    private func fetchCurrentUser() {
        guard let email = TokenUtil.getEmailFromToken() else { return }
        UserService.shared.fetchUserByEmail(email: email) { result in
            DispatchQueue.main.async {
                if case let .success(user) = result {
                    patientId = user.id
                    fetchPatientAppointments(userId: user.id)
                }
            }
        }
    }

    private func fetchPatientAppointments(userId: Int) {
        AppointmentService.shared.getAppointmentsByPatientId(userId) { result in
            DispatchQueue.main.async {
                if case let .success(appointments) = result {
                    allAppointments = appointments
                }
            }
        }
    }

    private func fetchDoctors() {
        guard let clinicId = selectedClinic?.id else { return }
        ClinicService.shared.getDoctorsByClinicId(clinicId: clinicId) { result in
            DispatchQueue.main.async {
                if case let .success(data) = result {
                    doctors = data
                }
            }
        }
    }

    private func fetchDoctorAppointments() {
        guard let id = selectedDoctorId else { return }
        let dateStr = formatDate(selectedDate)
        AppointmentService.shared.getAppointmentsByDoctorAndDate(doctorId: id, date: dateStr) { result in
            DispatchQueue.main.async {
                if case let .success(data) = result {
                    doctorAppointments = data
                    generateTimeSlots()
                }
            }
        }
    }

    private func generateTimeSlots() {
        let startHour = 8
        let endHour = 17
        let interval = 20
        let now = Date()
        let calendar = Calendar.current

        groupedTimeSlots = []
        pastTimes = []

        guard !calendar.isDateInWeekend(selectedDate) else { return }

        for hour in startHour..<endHour where hour != 12 {
            var slots: [String] = []

            for minute in stride(from: 0, to: 60, by: interval) {
                let slot = String(format: "%02d:%02d", hour, minute)
                if let slotDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate),
                   calendar.isDateInToday(selectedDate),
                   slotDate < now {
                    pastTimes.append(slot)
                }
                slots.append(slot)
            }

            groupedTimeSlots.append((hour: "\(hour):00", slots: slots))
        }
    }

    private func checkAppointmentConditions() {
        guard let patientId, let doctorId = selectedDoctorId, !selectedTime.isEmpty else {
            errorMessage = "Tüm alanları doldurun."
            return
        }

        if allAppointments.contains(where: {
            $0.date == formatDate(selectedDate) && $0.time.prefix(5) == selectedTime && $0.status == "AKTIF"
        }) {
            errorMessage = "Bu saat için aktif randevunuz zaten var."
            return
        }

        if allAppointments.contains(where: {
            $0.clinic.name == selectedClinic?.name && $0.status == "AKTIF"
        }) {
            showReplaceAlert = true
        } else {
            saveAppointment()
        }
    }

    private func saveAppointment() {
        guard let patientId, let doctorId = selectedDoctorId, let clinicId = selectedClinic?.id else { return }

        isSaving = true

        let selectedDoctor = doctors.first(where: { $0.id == doctorId })

        let request = AppointmentRequest(
            clinicId: clinicId,
            date: formatDate(selectedDate),
            time: selectedTime,
            description: descriptionText.isEmpty ? "Online randevu alındı." : descriptionText,
            doctor: DoctorReference(id: doctorId, name: selectedDoctor?.name, surname: selectedDoctor?.surname),
            patient: PatientReference(id: patientId)
        )

        AppointmentService.shared.createAppointment(request) { result in
            DispatchQueue.main.async {
                isSaving = false
                if case .success = result {
                    saveSuccess = true
                    resetForm()
                    presentationMode.wrappedValue.dismiss()
                } else {
                    errorMessage = "Randevu oluşturulamadı."
                }
            }
        }
    }

    private func isSlotDisabled(_ time: String) -> Bool {
        pastTimes.contains(time) || doctorAppointments.contains { $0.time.prefix(5) == time && $0.status == "AKTIF" }
    }

    private func resetForm() {
        selectedClinic = nil
        selectedDoctorId = nil
        selectedTime = ""
        descriptionText = ""
        groupedTimeSlots = []
        doctorAppointments = []
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
