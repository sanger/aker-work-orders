FactoryBot.define do
  factory :product do
    catalogue
    sequence(:name) { |i| "Product #{i}" }
    availability { true }
    uuid { SecureRandom.uuid }

    factory :product_with_processes do
      transient do
        process_count { 3 }
      end

      after(:create) do |product, evaluator|
        processes = create_list(:aker_process_with_work_orders, evaluator.process_count)

        processes.each_with_index do |process, index|
          create(:aker_product_process, product: product, aker_process: process, stage: index + 1)
        end
      end
    end
  end
end
