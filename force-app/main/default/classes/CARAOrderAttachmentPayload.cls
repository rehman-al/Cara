public class CARAOrderAttachmentPayload {
    public String orderReferenceNumber;
    public List<AttachmentItem> attachments;

    public class AttachmentItem {
        public String fileName;
        public String fileContent;
        public String contentType;
        public String description;
    }
}
