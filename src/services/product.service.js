import { pool } from '../config/db.js';

const mapProductRow = (row) => {
  if (!row) return null;
  return {
    id: String(row.id),
    name: row.name,
    barcode: row.barcode || undefined,
    price: Number(row.price),
    costPrice: Number(row.cost_price),
    stock: Number(row.quantity_in_stock),
    category: row.category || 'Uncategorized',
    description: row.description || '',
    sku: row.sku || undefined,
    isActive: row.is_active,
    minQuantity: row.min_quantity,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
};

export const getAllProducts = async () => {
  const { rows } = await pool.query(
    `SELECT id, name, description, sku, barcode, price, cost_price,
            quantity_in_stock, min_quantity, category, is_active, created_at, updated_at
     FROM products
     ORDER BY name ASC`
  );

  return rows.map(mapProductRow);
};

export const getProductById = async (id) => {
  const { rows } = await pool.query(
    `SELECT id, name, description, sku, barcode, price, cost_price,
            quantity_in_stock, min_quantity, category, is_active, created_at, updated_at
     FROM products
     WHERE id = $1`,
    [id]
  );

  return mapProductRow(rows[0]);
};

export const createProduct = async ({
  name,
  description,
  sku,
  barcode,
  price,
  costPrice,
  stock,
  minQuantity,
  category,
  isActive,
  createdBy,
}) => {
  const { rows } = await pool.query(
    `INSERT INTO products
      (name, description, sku, barcode, price, cost_price, quantity_in_stock, min_quantity, category, is_active, created_by)
     VALUES
      ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
     RETURNING id, name, description, sku, barcode, price, cost_price,
               quantity_in_stock, min_quantity, category, is_active, created_at, updated_at`,
    [name, description, sku || null, barcode || null, price, costPrice, stock, minQuantity, category, isActive, createdBy]
  );

  return mapProductRow(rows[0]);
};

export const updateProduct = async (id, updates) => {
  const current = await getProductById(id);
  if (!current) return null;

  const next = {
    name: updates.name ?? current.name,
    description: updates.description ?? current.description,
    sku: updates.sku ?? current.sku,
    barcode: updates.barcode ?? current.barcode,
    price: updates.price ?? current.price,
    costPrice: updates.costPrice ?? current.costPrice,
    stock: updates.stock ?? current.stock,
    minQuantity: updates.minQuantity ?? current.minQuantity,
    category: updates.category ?? current.category,
    isActive: updates.isActive ?? current.isActive,
  };

  const { rows } = await pool.query(
    `UPDATE products
     SET name = $1,
         description = $2,
         sku = $3,
         barcode = $4,
         price = $5,
         cost_price = $6,
         quantity_in_stock = $7,
         min_quantity = $8,
         category = $9,
         is_active = $10
     WHERE id = $11
     RETURNING id, name, description, sku, barcode, price, cost_price,
               quantity_in_stock, min_quantity, category, is_active, created_at, updated_at`,
    [
      next.name,
      next.description,
      next.sku || null,
      next.barcode || null,
      next.price,
      next.costPrice,
      next.stock,
      next.minQuantity,
      next.category,
      next.isActive,
      id,
    ]
  );

  return mapProductRow(rows[0]);
};

export const deleteProduct = async (id) => {
  const { rowCount } = await pool.query('DELETE FROM products WHERE id = $1', [id]);
  return rowCount > 0;
};
