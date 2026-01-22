// Static data for POS system - replaces database during frontend development

// Sample users
export const users = [
  {
    id: 1,
    username: 'admin',
    email: 'admin@pos.com',
    password: '$2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', // 'password'
    role: 'ADMIN',
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  },
  {
    id: 2,
    username: 'cashier1',
    email: 'cashier1@pos.com',
    password: '$2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', // 'password'
    role: 'CASHIER',
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  },
  {
    id: 3,
    username: 'manager1',
    email: 'manager1@pos.com',
    password: '$2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', // 'password'
    role: 'MANAGER',
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  }
];

// Sample products
export const products = [
  {
    id: 1,
    name: 'Coffee - Large',
    description: 'Large cup of premium coffee',
    price: 4.50,
    category: 'Beverages',
    sku: 'COF-LRG-001',
    stock: 100,
    isActive: true,
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  },
  {
    id: 2,
    name: 'Coffee - Medium',
    description: 'Medium cup of premium coffee',
    price: 3.50,
    category: 'Beverages',
    sku: 'COF-MED-002',
    stock: 150,
    isActive: true,
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  },
  {
    id: 3,
    name: 'Coffee - Small',
    description: 'Small cup of premium coffee',
    price: 2.50,
    category: 'Beverages',
    sku: 'COF-SML-003',
    stock: 200,
    isActive: true,
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  },
  {
    id: 4,
    name: 'Croissant',
    description: 'Fresh butter croissant',
    price: 3.00,
    category: 'Food',
    sku: 'FOOD-CRO-004',
    stock: 50,
    isActive: true,
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  },
  {
    id: 5,
    name: 'Sandwich',
    description: 'Club sandwich with fries',
    price: 8.50,
    category: 'Food',
    sku: 'FOOD-SND-005',
    stock: 30,
    isActive: true,
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  },
  {
    id: 6,
    name: 'Juice - Orange',
    description: 'Fresh orange juice',
    price: 4.00,
    category: 'Beverages',
    sku: 'BEV-ORG-006',
    stock: 80,
    isActive: true,
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  },
  {
    id: 7,
    name: 'Cake Slice',
    description: 'Chocolate cake slice',
    price: 5.50,
    category: 'Desserts',
    sku: 'DES-CAK-007',
    stock: 25,
    isActive: true,
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  },
  {
    id: 8,
    name: 'Tea - Green',
    description: 'Green tea with honey',
    price: 3.00,
    category: 'Beverages',
    sku: 'BEV-GRN-008',
    stock: 120,
    isActive: true,
    createdAt: new Date('2024-01-01'),
    updatedAt: new Date('2024-01-01')
  }
];

// Sample orders
export const orders = [
  {
    id: 1,
    userId: 2,
    items: [
      { productId: 1, quantity: 2, price: 4.50 },
      { productId: 4, quantity: 1, price: 3.00 }
    ],
    subtotal: 12.00,
    tax: 1.20,
    total: 13.20,
    status: 'COMPLETED',
    paymentMethod: 'CASH',
    createdAt: new Date('2024-01-15T10:30:00'),
    updatedAt: new Date('2024-01-15T10:30:00')
  },
  {
    id: 2,
    userId: 2,
    items: [
      { productId: 2, quantity: 1, price: 3.50 },
      { productId: 6, quantity: 1, price: 4.00 }
    ],
    subtotal: 7.50,
    tax: 0.75,
    total: 8.25,
    status: 'COMPLETED',
    paymentMethod: 'CARD',
    createdAt: new Date('2024-01-15T11:15:00'),
    updatedAt: new Date('2024-01-15T11:15:00')
  },
  {
    id: 3,
    userId: 3,
    items: [
      { productId: 5, quantity: 1, price: 8.50 },
      { productId: 7, quantity: 1, price: 5.50 },
      { productId: 8, quantity: 1, price: 3.00 }
    ],
    subtotal: 17.00,
    tax: 1.70,
    total: 18.70,
    status: 'PENDING',
    paymentMethod: 'CASH',
    createdAt: new Date('2024-01-15T12:45:00'),
    updatedAt: new Date('2024-01-15T12:45:00')
  }
];

// Helper functions for static data operations
export let nextUserId = users.length + 1;
export let nextProductId = products.length + 1;
export let nextOrderId = orders.length + 1;
