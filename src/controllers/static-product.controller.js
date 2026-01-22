import { StatusCodes } from 'http-status-codes';
import { products, nextProductId } from '../data/staticData.js';

// Get all products
export const list = async (req, res) => {
  try {
    const { category, search } = req.query;
    
    let filteredProducts = products.filter(product => product.isActive);
    
    // Filter by category
    if (category) {
      filteredProducts = filteredProducts.filter(product => 
        product.category.toLowerCase() === category.toLowerCase()
      );
    }
    
    // Search by name or description
    if (search) {
      const searchTerm = search.toLowerCase();
      filteredProducts = filteredProducts.filter(product => 
        product.name.toLowerCase().includes(searchTerm) ||
        product.description.toLowerCase().includes(searchTerm)
      );
    }

    res.status(StatusCodes.OK).json({
      status: 'success',
      data: {
        products: filteredProducts,
        count: filteredProducts.length
      }
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Failed to fetch products'
    });
  }
};

// Get single product
export const getOne = async (req, res) => {
  try {
    const { id } = req.params;
    
    const product = products.find(p => p.id === parseInt(id) && p.isActive);
    
    if (!product) {
      return res.status(StatusCodes.NOT_FOUND).json({
        status: 'error',
        message: 'Product not found'
      });
    }

    res.status(StatusCodes.OK).json({
      status: 'success',
      data: {
        product
      }
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Failed to fetch product'
    });
  }
};

// Create new product
export const create = async (req, res) => {
  try {
    const { name, description, price, category, sku, stock = 0 } = req.body;

    // Check if SKU already exists
    const existingProduct = products.find(p => p.sku === sku);
    if (existingProduct) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'SKU already exists'
      });
    }

    const newProduct = {
      id: products.length + 1,
      name,
      description,
      price: parseFloat(price),
      category,
      sku,
      stock: parseInt(stock),
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    // For static data, we'll just return success without actually modifying the array
    res.status(StatusCodes.CREATED).json({
      status: 'success',
      data: {
        product: newProduct
      }
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Failed to create product'
    });
  }
};

// Update product
export const update = async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, price, category, sku, stock } = req.body;

    const productIndex = products.findIndex(p => p.id === parseInt(id));
    
    if (productIndex === -1) {
      return res.status(StatusCodes.NOT_FOUND).json({
        status: 'error',
        message: 'Product not found'
      });
    }

    // Check if SKU already exists (excluding current product)
    if (sku) {
      const existingProduct = products.find(p => p.sku === sku && p.id !== parseInt(id));
      if (existingProduct) {
        return res.status(StatusCodes.BAD_REQUEST).json({
          status: 'error',
          message: 'SKU already exists'
        });
      }
    }

    const updatedProduct = {
      ...products[productIndex],
      name: name || products[productIndex].name,
      description: description || products[productIndex].description,
      price: price ? parseFloat(price) : products[productIndex].price,
      category: category || products[productIndex].category,
      sku: sku || products[productIndex].sku,
      stock: stock !== undefined ? parseInt(stock) : products[productIndex].stock,
      updatedAt: new Date()
    };

    // For static data, we'll just return the updated product without actually modifying the array
    res.status(StatusCodes.OK).json({
      status: 'success',
      data: {
        product: updatedProduct
      }
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Failed to update product'
    });
  }
};

// Delete product (soft delete)
export const remove = async (req, res) => {
  try {
    const { id } = req.params;

    const productIndex = products.findIndex(p => p.id === parseInt(id));
    
    if (productIndex === -1) {
      return res.status(StatusCodes.NOT_FOUND).json({
        status: 'error',
        message: 'Product not found'
      });
    }

    // For static data, we'll just return success without actually modifying the array
    res.status(StatusCodes.OK).json({
      status: 'success',
      message: 'Product deleted successfully'
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Failed to delete product'
    });
  }
};
