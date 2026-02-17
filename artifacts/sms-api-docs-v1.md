# **SMS API Documentation (HTTP API)**

\[\!IMPORTANT\]

**Modern Alternative:** The most up-to-date method is the **JSON API**. While this HTTP API endpoint remains supported long-term, it is recommended to use the JSON API for all new integrations.

## ---

**Request Overview**

* **HTTP Methods:** POST or GET  
* **Content-Type:** application/x-www-form-urlencoded

### **Request Parameters**

| Parameter | Description | Required |
| :---- | :---- | :---- |
| **apikey** | Your unique API key obtained from the administration panel. | **Yes** |
| **number** | Recipient's phone number (e.g., 420777111222). | **Yes** |
| **message** | The text content of the message. | **Yes** |
| **sender** | The sender name or number. | No |
| **gateway** | Type of sending gateway. | No |
| **time** | Scheduled date and time (e.g., 2025-01-01T23:59:59). | No |
| **type** | Message type setting. Use utf to preserve diacritics. | No |

## ---

**Response Handling**

### **Success Response**

* **HTTP Status:** 200 OK  
* **Content-Type:** text/plain

The response is returned in a pipe-separated text format:

OK|550e8400-e29b-41d4-a716-446655440000|420777111222

| Value | Description |
| :---- | :---- |
| **OK** | Message successfully accepted and queued. |
| **ID** | Unique Message ID (UUID). |
| **Number** | The recipient's phone number. |

### **Error Response**

* **HTTP Status:** 4xx or 5xx  
* **Content-Type:** text/plain

The error response follows this format:

ERROR|102

| Value | Description |
| :---- | :---- |
| **ERROR** | The message was not sent. |
| **Code** | Specific error code indicating the cause. |

## ---

**Additional Features**

* **Diacritics:** To ensure special characters (like Czech accents) are delivered correctly, ensure the type parameter is set to utf.  
* **Scheduling:** Use the time parameter to delay delivery to a specific future timestamp.

Would you like me to generate a code snippet in a specific programming language (like Python or PHP) to help you test this API?
