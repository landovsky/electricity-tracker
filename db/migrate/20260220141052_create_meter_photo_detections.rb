class CreateMeterPhotoDetections < ActiveRecord::Migration[8.1]
  def change
    create_table :meter_photo_detections do |t|
      t.string     :session_id,     null: false, index: true
      t.references :property,       null: false, foreign_key: true
      t.references :meter,          foreign_key: true
      t.string     :status,         null: false, default: "processing"
      t.decimal    :detected_value, precision: 10, scale: 2
      t.float      :confidence
      t.text       :error_message
      t.text       :raw_ocr_text
      t.json       :llm_response

      t.timestamps
    end
  end
end
