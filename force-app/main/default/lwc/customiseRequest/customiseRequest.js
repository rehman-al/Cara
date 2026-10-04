import { LightningElement, wire } from 'lwc';
import getActiveOptions from '@salesforce/apex/CustomiseRequestController.getActiveOptions';
import submitCustomisationRequestV2 from '@salesforce/apex/CustomiseRequestController.submitCustomisationRequestV2';

const STEP_LABELS = {
    en: ['Piece', 'Your vision', 'Details', 'Review'],
    ar: ['القطعة', 'رؤيتك', 'التفاصيل', 'المراجعة']
};
const CONTACT_OPTIONS = ['Email', 'Phone', 'WhatsApp'];
const CATEGORY_ORDER = [
    'Ring',
    'Engagement Ring',
    'Necklace',
    'Earrings',
    'Bracelet',
    'Pendant',
    'Something Else'
];
const CATEGORY_COPY = {
    en: {
        Ring: 'Cocktail, eternity and signature bands',
        'Engagement Ring': 'Solitaire, halo or a bespoke setting',
        Necklace: 'Rivières, pendants and chains',
        Earrings: 'Studs, drops and hoops',
        Bracelet: 'Tennis lines, bangles and cuffs',
        Pendant: 'Personal charms and lockets',
        'Something Else': 'Tell us what you have in mind'
    },
    ar: {
        Ring: 'خواتم كوكتيل وخواتم أبدية وتصاميم مميزة',
        'Engagement Ring': 'خاتم منفرد أو هالة أو ترصيع مصمم حسب الطلب',
        Necklace: 'عقود ريفييرا وتعليقات وسلاسل',
        Earrings: 'أقراط مسمارية ومتدلية وحلقية',
        Bracelet: 'أساور تنس وأساور صلبة وأساور مفتوحة',
        Pendant: 'تعليقات شخصية وتمائم',
        'Something Else': 'أخبرنا بما يدور في خيالك'
    }
};

const OPTION_LABELS_AR = {
    Ring: 'خاتم',
    'Engagement Ring': 'خاتم خطوبة',
    Necklace: 'عقد',
    Earrings: 'أقراط',
    Bracelet: 'سوار',
    Pendant: 'تعليقة',
    'Something Else': 'شيء آخر',
    'Yellow Gold': 'ذهب أصفر',
    'White Gold': 'ذهب أبيض',
    'Rose Gold': 'ذهب وردي',
    Platinum: 'بلاتين',
    'Not sure yet': 'لست متأكدًا بعد',
    Email: 'البريد الإلكتروني',
    Phone: 'الهاتف',
    WhatsApp: 'واتساب',
    'No rush': 'لا يوجد موعد محدد',
    'No particular rush': 'لا يوجد موعد محدد',
    'Within 1 month': 'خلال شهر',
    'Within 3 months': 'خلال 3 أشهر',
    'For a specific date': 'لموعد محدد',
    '1-2 months': 'شهر إلى شهرين',
    '1 – 2 months': 'شهر إلى شهرين',
    '3-6 months': '3 إلى 6 أشهر',
    '3 – 6 months': '3 إلى 6 أشهر',
    'As soon as possible': 'في أقرب وقت ممكن',
    'Under AED 5,000': 'أقل من 5,000 درهم',
    'Under AED 10,000': 'أقل من 10,000 درهم',
    'AED 5,000 - 10,000': '5,000 – 10,000 درهم',
    'AED 10,000 - 25,000': '10,000 – 25,000 درهم',
    'AED 10,000 – 25,000': '10,000 – 25,000 درهم',
    'AED 25,000 – 50,000': '25,000 – 50,000 درهم',
    'AED 50,000 – 100,000': '50,000 – 100,000 درهم',
    'Above AED 100,000': 'أكثر من 100,000 درهم',
    'AED 25,000+': '25,000 درهم فأكثر'
};
const MAX_FILE_BYTES = 4 * 1024 * 1024;
const ALLOWED_EXTENSIONS = ['png', 'jpg', 'jpeg'];
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const COPY = {
    en: {
        eyebrow: 'Bespoke atelier',
        submittedTitle: 'Your request is with us',
        submittedIntro: 'A member of our atelier will personally review your brief.',
        title: 'Create something entirely yours',
        intro: 'Tell us what you have in mind and our designers will bring it to life — from a single stone to a complete commission.',
        confirmationAria: 'Request confirmation',
        thankYou: 'Thank you',
        confirmationBody: "We'll be in touch within two business days to discuss your vision, materials and next steps. A copy has been noted against your details.",
        backHome: 'Back to home',
        progressAria: 'Customisation progress',
        loadingOptions: 'Loading options',
        pieceQuestion: 'What would you like to customise?',
        shareIdea: 'How would you like to share your idea?',
        uploadReference: 'Upload a reference',
        describeWords: 'Describe in words',
        referenceImage: 'Reference image',
        imageAlt: 'Your reference',
        removeImage: 'Remove image',
        chooseImage: 'Choose an image',
        imageTypes: 'PNG or JPG',
        imageHint: 'A sketch, inspiration photo or a piece you love. Optional, but it helps.',
        descriptionUpload: 'Notes for our designers',
        descriptionDescribe: "Describe what you're looking for",
        descriptionPlaceholder: "I'd love a rose-gold ring with an emerald centre stone, inspired by…",
        descriptionHint: 'Style, stones, size, occasion — the more detail, the better.',
        preferredMetal: 'Preferred metal',
        stoneType: 'Stone type',
        timeline: 'Timeline',
        budgetGuide: 'Budget guide',
        fullName: 'Full name',
        email: 'Email',
        phone: 'Phone',
        preferredContact: 'Preferred contact method',
        namePlaceholder: 'Your name',
        emailPlaceholder: 'you@email.com',
        phonePlaceholder: '+971 …',
        reviewQuestion: 'A last look before we begin.',
        back: '← Back',
        continue: 'Continue',
        submitRequest: 'Submit request',
        submitting: 'Submitting…',
        piece: 'Piece',
        idea: 'Idea',
        description: 'Description',
        metal: 'Metal',
        stone: 'Stone',
        budget: 'Budget',
        name: 'Name',
        contactVia: 'Contact via',
        brief: 'Brief',
        contact: 'Contact',
        reference: 'Reference',
        writtenBrief: 'Written brief',
        referenceNotes: 'Reference + notes',
        optionsError: 'Unable to load customisation options. Please refresh the page.',
        fileTypeError: 'Please choose a PNG or JPG image.',
        fileSizeError: 'Reference images must be smaller than 4MB.',
        fileReadError: 'The image could not be read. Please try another file.',
        submitError: 'We could not submit your request. Please try again.'
    },
    ar: {
        eyebrow: 'مشغل المجوهرات حسب الطلب',
        submittedTitle: 'طلبك الآن بين أيدينا',
        submittedIntro: 'سيقوم أحد خبراء مشغلنا بمراجعة تفاصيل طلبك بعناية.',
        title: 'ابتكر قطعة تخصك وحدك',
        intro: 'أخبرنا بما يدور في خيالك، وسيحوّله مصممونا إلى حقيقة — من حجر واحد إلى تصميم متكامل حسب الطلب.',
        confirmationAria: 'تأكيد الطلب',
        thankYou: 'شكرًا لك',
        confirmationBody: 'سنتواصل معك خلال يومي عمل لمناقشة رؤيتك والمواد والخطوات التالية. تم حفظ نسخة من الطلب ضمن بياناتك.',
        backHome: 'العودة إلى الصفحة الرئيسية',
        progressAria: 'مراحل طلب التخصيص',
        loadingOptions: 'جارٍ تحميل الخيارات',
        pieceQuestion: 'ما القطعة التي ترغب في تخصيصها؟',
        shareIdea: 'كيف تود مشاركة فكرتك؟',
        uploadReference: 'تحميل صورة مرجعية',
        describeWords: 'الوصف بالكلمات',
        referenceImage: 'الصورة المرجعية',
        imageAlt: 'الصورة المرجعية التي اخترتها',
        removeImage: 'إزالة الصورة',
        chooseImage: 'اختر صورة',
        imageTypes: 'PNG أو JPG',
        imageHint: 'رسم أو صورة ملهمة أو قطعة أعجبتك. هذا اختياري، لكنه يساعدنا.',
        descriptionUpload: 'ملاحظات لمصممينا',
        descriptionDescribe: 'صف القطعة التي تبحث عنها',
        descriptionPlaceholder: 'أرغب في خاتم من الذهب الوردي يتوسطه حجر زمرد، مستوحى من…',
        descriptionHint: 'اذكر الأسلوب والأحجار والمقاس والمناسبة — كلما زادت التفاصيل كان أفضل.',
        preferredMetal: 'المعدن المفضل',
        stoneType: 'نوع الحجر',
        timeline: 'المدة الزمنية',
        budgetGuide: 'الميزانية التقريبية',
        fullName: 'الاسم الكامل',
        email: 'البريد الإلكتروني',
        phone: 'رقم الهاتف',
        preferredContact: 'وسيلة التواصل المفضلة',
        namePlaceholder: 'اسمك',
        emailPlaceholder: 'you@email.com',
        phonePlaceholder: '+971 …',
        reviewQuestion: 'راجع التفاصيل قبل أن نبدأ.',
        back: 'رجوع →',
        continue: 'متابعة',
        submitRequest: 'إرسال الطلب',
        submitting: 'جارٍ الإرسال…',
        piece: 'القطعة',
        idea: 'الفكرة',
        description: 'الوصف',
        metal: 'المعدن',
        stone: 'الحجر',
        budget: 'الميزانية',
        name: 'الاسم',
        contactVia: 'التواصل عبر',
        brief: 'التفاصيل',
        contact: 'بيانات التواصل',
        reference: 'مرجع',
        writtenBrief: 'وصف مكتوب',
        referenceNotes: 'صورة مرجعية وملاحظات',
        optionsError: 'تعذر تحميل خيارات التخصيص. يرجى تحديث الصفحة.',
        fileTypeError: 'يرجى اختيار صورة بصيغة PNG أو JPG.',
        fileSizeError: 'يجب أن يكون حجم الصورة المرجعية أقل من 4 ميجابايت.',
        fileReadError: 'تعذرت قراءة الصورة. يرجى تجربة ملف آخر.',
        submitError: 'تعذر إرسال طلبك. يرجى المحاولة مرة أخرى.'
    }
};

export default class CustomiseRequest extends LightningElement {
    step = 0;
    submitted = false;
    isSubmitting = false;
    isFileReading = false;
    submitError = '';
    fileError = '';

    optionsByType = {};
    optionsLoading = true;
    optionsError = '';

    pieceType = null;
    briefType = 'upload';
    fileName = '';
    filePreviewUrl = '';
    fileBase64 = '';
    fileContentType = '';
    description = '';
    preferredMetal = null;
    stoneType = null;
    color = null;
    budgetGuide = null;
    timeline = null;

    fullName = '';
    email = '';
    phone = '';
    preferredContactMethod = 'Email';

    resultCaseNumber = '';
    resultFileAttached = false;
    resultWarning = '';

    storefrontHomeUrl = '';
    parentOrigin = '';
    heightObserver = null;
    heightObserved = false;

    locale = 'en-AE';
    language = 'en';
    direction = 'ltr';

    connectedCallback() {
        this.resolveLocale();
        this.resolveStorefrontHomeUrl();
        window.addEventListener('resize', this.reportHeight);
        window.addEventListener('message', this.handleParentMessage);
    }

    renderedCallback() {
        const shell = this.template.querySelector('.cr-shell');
        if (!shell) return;

        if (!this.heightObserved && typeof ResizeObserver !== 'undefined') {
            this.heightObserver = new ResizeObserver(this.reportHeight);
            this.heightObserver.observe(shell);
            this.heightObserved = true;
        }
        window.requestAnimationFrame(this.reportHeight);
    }

    disconnectedCallback() {
        this.clearFile();
        if (this.heightObserver) this.heightObserver.disconnect();
        window.removeEventListener('resize', this.reportHeight);
        window.removeEventListener('message', this.handleParentMessage);
    }


    resolveLocale() {
        try {
            const suppliedLocale =
                new URL(window.location.href).searchParams.get('locale') || 'en-AE';
            this.language = suppliedLocale.toLowerCase().startsWith('ar') ? 'ar' : 'en';
            this.locale = this.language;
            this.direction = this.language === 'ar' ? 'rtl' : 'ltr';
        } catch (error) {
            this.locale = 'en-AE';
            this.language = 'en';
            this.direction = 'ltr';
        }
    }

    resolveStorefrontHomeUrl() {
        try {
            const suppliedUrl = new URL(window.location.href).searchParams.get('returnUrl');
            const referrerOrigin = window.document.referrer
                ? new URL(window.document.referrer).origin
                : '';
            if (!suppliedUrl || !referrerOrigin) return;

            const destination = new URL(suppliedUrl);
            const isWebUrl = destination.protocol === 'https:' ||
                (destination.protocol === 'http:' &&
                    ['localhost', '127.0.0.1'].includes(destination.hostname));
            if (isWebUrl && destination.origin === referrerOrigin) {
                this.storefrontHomeUrl = destination.href;
                this.parentOrigin = destination.origin;
            }
        } catch (error) {
            this.storefrontHomeUrl = '';
            this.parentOrigin = '';
        }
    }

    reportHeight = () => {
        if (!this.parentOrigin || window.parent === window) return;
        const shell = this.template.querySelector('.cr-shell');
        if (!shell) return;

        const height = Math.ceil(shell.getBoundingClientRect().bottom);
        if (height >= 400 && height <= 12000) {
            window.parent.postMessage({ type: 'cara:customise:height', height }, this.parentOrigin);
        }
    };

    handleParentMessage = (event) => {
        if (event.source === window.parent &&
            event.origin === this.parentOrigin &&
            event.data &&
            event.data.type === 'cara:customise:measure') {
            this.reportHeight();
        }
    };

    @wire(getActiveOptions)
    wiredOptions(result) {
        this.optionsLoading = false;
        if (result.data) {
            this.optionsByType = result.data;
            this.optionsError = '';
        } else if (result.error) {
            this.optionsError =
                (this.language === 'en' && result.error.body && result.error.body.message) ||
                this.text.optionsError;
        }
    }

    get text() { return COPY[this.language]; }
    get stepLabels() { return STEP_LABELS[this.language]; }

    get isStep0() { return this.step === 0; }
    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }
    get isUploadMode() { return this.briefType === 'upload'; }
    get isDescribeMode() { return this.briefType === 'describe'; }
    get hasFile() { return Boolean(this.filePreviewUrl); }
    get hasStorefrontHomeUrl() { return Boolean(this.storefrontHomeUrl); }

    get descriptionLabel() {
        return this.isUploadMode ? this.text.descriptionUpload : this.text.descriptionDescribe;
    }

    get stepperItems() {
        return this.stepLabels.map((label, index) => ({
            key: String(index),
            number: '0' + (index + 1),
            label,
            cssClass: 'cr-step-item' +
                (index === this.step ? ' cr-step-item_current' : '') +
                (index < this.step ? ' cr-step-item_complete' : ''),
            separatorClass: 'cr-step-separator' +
                (index < this.step ? ' cr-step-separator_complete' : ''),
            showSeparator: index < this.stepLabels.length - 1
        }));
    }

    rawOptions(type) {
        return this.optionsByType && this.optionsByType[type] ? this.optionsByType[type] : [];
    }

    get pieceOptions() {
        const order = (value) => {
            const index = CATEGORY_ORDER.indexOf(value);
            return index < 0 ? CATEGORY_ORDER.length : index;
        };
        return [...this.rawOptions('Category')]
            .sort((a, b) => order(a.value) - order(b.value))
            .map((opt) => ({
                value: opt.value,
                label: this.displayValue(opt.value),
                blurb: CATEGORY_COPY[this.language][opt.value] || opt.description || '',
                selected: opt.value === this.pieceType,
                cssClass: 'cr-option-card' +
                    (opt.value === this.pieceType ? ' cr-option-card_selected' : '')
            }));
    }

    get uploadModeCssClass() {
        return 'cr-segmented-option' +
            (this.isUploadMode ? ' cr-segmented-option_selected' : '');
    }

    get describeModeCssClass() {
        return 'cr-segmented-option' +
            (this.isDescribeMode ? ' cr-segmented-option_selected' : '');
    }

    get metalOptions() {
        return this.chipOptions(this.rawOptions('Metal Type'), this.preferredMetal);
    }
    get stoneOptions() {
        return this.chipOptions(this.rawOptions('Stone Type'), this.stoneType);
    }
    get timelineOptions() {
        return this.chipOptions(this.rawOptions('Timeline'), this.timeline);
    }
    get budgetOptions() {
        return this.chipOptions(this.rawOptions('Budget Guide'), this.budgetGuide);
    }
    get contactOptions() {
        return this.chipOptions(CONTACT_OPTIONS.map((value) => ({ value })), this.preferredContactMethod);
    }

    chipOptions(options, selectedValue) {
        return options.map((opt) => ({
            value: opt.value,
            label: this.displayValue(opt.value),
            selected: opt.value === selectedValue,
            cssClass: 'cr-chip' + (opt.value === selectedValue ? ' cr-chip_selected' : '')
        }));
    }

    displayValue(value) {
        if (!value) return '';
        if (this.language === 'ar' && OPTION_LABELS_AR[value]) {
            return OPTION_LABELS_AR[value];
        }
        if (value === 'Something Else') return 'Something else';
        return value.replace(/ - /g, ' – ');
    }

    get pieceTypeLabel() {
        return this.displayValue(this.pieceType);
    }
    get confirmationTitle() {
        if (this.language === 'ar') {
            return 'نتطلع إلى ابتكار ' + (this.pieceTypeLabel || 'قطعتك');
        }
        return "We can't wait to create your " + (this.pieceTypeLabel.toLowerCase() || 'piece');
    }
    get briefSummary() {
        return this.hasFile
            ? this.text.reference + ': ' + this.fileName
            : this.text.writtenBrief;
    }
    get showBack() { return this.step > 0; }
    get nextLabel() {
        return this.step === this.stepLabels.length - 1
            ? this.text.submitRequest
            : this.text.continue;
    }
    get stepProgressLabel() {
        return (this.step + 1) + ' / ' + this.stepLabels.length;
    }
    get currentStepLabel() {
        return this.stepLabels[this.step];
    }
    get progressPercent() {
        return 'width:' + (((this.step + 1) / this.stepLabels.length) * 100) + '%';
    }

    get reviewItems() {
        const items = [
            { label: this.text.piece, value: this.pieceTypeLabel },
            { label: this.text.idea, value: this.briefSummary },
            { label: this.text.description, value: this.description }
        ];
        if (this.preferredMetal) {
            items.push({ label: this.text.metal, value: this.displayValue(this.preferredMetal) });
        }
        if (this.stoneType) {
            items.push({ label: this.text.stone, value: this.displayValue(this.stoneType) });
        }
        if (this.budgetGuide) {
            items.push({ label: this.text.budget, value: this.displayValue(this.budgetGuide) });
        }
        if (this.timeline) {
            items.push({ label: this.text.timeline, value: this.displayValue(this.timeline) });
        }
        items.push({ label: this.text.name, value: this.fullName });
        items.push({ label: this.text.email, value: this.email });
        if (this.phone) items.push({ label: this.text.phone, value: this.phone });
        items.push({
            label: this.text.contactVia,
            value: this.displayValue(this.preferredContactMethod)
        });
        return items.map((item, index) => ({ ...item, key: item.label + '-' + index }));
    }

    get confirmationSummary() {
        const items = [
            { label: this.text.piece, value: this.pieceTypeLabel },
            {
                label: this.text.brief,
                value: this.hasFile ? this.text.referenceNotes : this.text.writtenBrief
            }
        ];
        if (this.preferredMetal) {
            items.push({ label: this.text.metal, value: this.displayValue(this.preferredMetal) });
        }
        if (this.budgetGuide) {
            items.push({ label: this.text.budget, value: this.displayValue(this.budgetGuide) });
        }
        items.push({
            label: this.text.contact,
            value: this.fullName + ' · ' + this.displayValue(this.preferredContactMethod)
        });
        return items.map((item, index) => ({ ...item, key: item.label + '-' + index }));
    }

    get canContinue() {
        if (this.step === 0) return Boolean(this.pieceType);
        if (this.step === 1) return this.description.trim().length > 0;
        if (this.step === 2) {
            return this.fullName.trim().length > 1 && EMAIL_PATTERN.test(this.email.trim());
        }
        return true;
    }
    get nextDisabled() {
        return !this.canContinue || this.isSubmitting || this.isFileReading;
    }

    handlePieceSelect(event) { this.pieceType = event.currentTarget.dataset.value; }
    handleBriefTypeChange(event) { this.briefType = event.currentTarget.dataset.value; }
    handleDescriptionChange(event) { this.description = event.target.value; }
    handleMetalSelect(event) {
        const value = event.currentTarget.dataset.value;
        this.preferredMetal = this.preferredMetal === value ? null : value;
    }
    handleStoneSelect(event) {
        const value = event.currentTarget.dataset.value;
        this.stoneType = this.stoneType === value ? null : value;
    }
    handleTimelineSelect(event) {
        const value = event.currentTarget.dataset.value;
        this.timeline = this.timeline === value ? null : value;
    }
    handleBudgetSelect(event) {
        const value = event.currentTarget.dataset.value;
        this.budgetGuide = this.budgetGuide === value ? null : value;
    }
    handleContactSelect(event) { this.preferredContactMethod = event.currentTarget.dataset.value; }
    handleNameChange(event) { this.fullName = event.target.value; }
    handleEmailChange(event) { this.email = event.target.value; }
    handlePhoneChange(event) { this.phone = event.target.value; }

    handleFileChange(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) return;
        this.fileError = '';

        const extension = file.name.includes('.') ? file.name.split('.').pop().toLowerCase() : '';
        if (!ALLOWED_EXTENSIONS.includes(extension)) {
            this.fileError = this.text.fileTypeError;
            event.target.value = '';
            return;
        }
        if (file.size > MAX_FILE_BYTES) {
            this.fileError = this.text.fileSizeError;
            event.target.value = '';
            return;
        }

        this.clearFile();
        this.fileName = file.name;
        this.fileContentType = file.type || (extension === 'png' ? 'image/png' : 'image/jpeg');
        this.filePreviewUrl = URL.createObjectURL(file);
        this.isFileReading = true;

        const reader = new FileReader();
        reader.onload = () => {
            const result = typeof reader.result === 'string' ? reader.result : '';
            this.fileBase64 = result.split(',')[1] || '';
            this.isFileReading = false;
        };
        reader.onerror = () => {
            this.fileError = this.text.fileReadError;
            this.clearFile();
            this.isFileReading = false;
        };
        reader.readAsDataURL(file);
    }

    handleRemoveFile() {
        this.clearFile();
        const input = this.template.querySelector('.cr-hidden-input');
        if (input) input.value = '';
    }

    clearFile() {
        if (this.filePreviewUrl) URL.revokeObjectURL(this.filePreviewUrl);
        this.fileName = '';
        this.filePreviewUrl = '';
        this.fileBase64 = '';
        this.fileContentType = '';
    }

    handleBack() {
        this.submitError = '';
        this.step = Math.max(0, this.step - 1);
    }

    async handleNext() {
        if (this.nextDisabled) return;
        this.submitError = '';

        if (this.step < this.stepLabels.length - 1) {
            this.step += 1;
            return;
        }

        this.isSubmitting = true;
        try {
            const result = await submitCustomisationRequestV2({
                inputJson: JSON.stringify({
                    pieceType: this.pieceType,
                    briefType: this.briefType,
                    description: this.description.trim(),
                    preferredMetal: this.preferredMetal,
                    stoneType: this.stoneType,
                    color: this.color,
                    budgetGuide: this.budgetGuide,
                    timeline: this.timeline,
                    fullName: this.fullName.trim(),
                    email: this.email.trim(),
                    phone: this.phone ? this.phone.trim() : '',
                    preferredContactMethod: this.preferredContactMethod,
                    fileName: this.fileName,
                    fileContentType: this.fileContentType,
                    fileBase64: this.fileBase64
                })
            });

            this.resultCaseNumber = result.caseNumber;
            this.resultFileAttached = result.fileAttached;
            this.resultWarning = result.warning || '';
            this.submitted = true;
        } catch (error) {
            this.submitError =
                (this.language === 'en' && error && error.body && error.body.message) ||
                this.text.submitError;
        } finally {
            this.isSubmitting = false;
        }
    }
}