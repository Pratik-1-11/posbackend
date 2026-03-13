
import supabase from '../config/supabase.js';

/**
 * Double-Entry Accounting Utility
 */

/**
 * Create a Journal Entry with lines
 * 
 * @param {Object} params
 * @param {string} params.tenantId
 * @param {string} params.branchId
 * @param {string} params.referenceId - ID of the source transaction (sale, purchase, etc.)
 * @param {string} params.referenceType - 'SALE', 'PURCHASE', 'EXPENSE', 'PAYMENT'
 * @param {string} params.description
 * @param {string} params.date - Entry date
 * @param {Array} params.lines - Array of lines { systemCode or accountId, debit, credit }
 * @param {string} params.createdBy - User ID
 */
export async function createJournalEntry({
    tenantId,
    branchId,
    referenceId,
    referenceType,
    description,
    date,
    lines,
    createdBy
}) {
    try {
        // 1. Resolve Account IDs if systemCodes are provided
        const resolvedLines = [];

        // Get all system accounts for this tenant to avoid multiple queries
        const { data: accounts, error: acctError } = await supabase
            .from('accounts')
            .select('id, system_code')
            .eq('tenant_id', tenantId);

        if (acctError) throw acctError;

        const accountMap = {};
        accounts.forEach(a => {
            if (a.system_code) accountMap[a.system_code] = a.id;
        });

        for (const line of lines) {
            let accountId = line.accountId;

            if (line.systemCode && accountMap[line.systemCode]) {
                accountId = accountMap[line.systemCode];
            }

            if (!accountId) {
                console.warn(`[Accounting] Could not resolve account for systemCode: ${line.systemCode}`);
                continue;
            }

            resolvedLines.push({
                account_id: accountId,
                debit: line.debit || 0,
                credit: line.credit || 0
            });
        }

        if (resolvedLines.length === 0) {
            console.warn('[Accounting] No valid lines for journal entry. Skipping.');
            return null;
        }

        // 2. Insert Header
        const { data: entry, error: entryError } = await supabase
            .from('journal_entries')
            .insert({
                tenant_id: tenantId,
                branch_id: branchId,
                reference_id: referenceId,
                reference_type: referenceType,
                description,
                entry_date: date || new Date().toISOString().split('T')[0],
                created_by: createdBy
            })
            .select()
            .single();

        if (entryError) throw entryError;

        // 3. Insert Lines
        const linesToInsert = resolvedLines.map(l => ({
            entry_id: entry.id,
            ...l
        }));

        const { error: linesError } = await supabase
            .from('journal_entry_lines')
            .insert(linesToInsert);

        if (linesError) throw linesError;

        return entry;
    } catch (error) {
        console.error('[Accounting Utility Error]', error);
        // We don't necessarily want to crash the main process if accounting fails, 
        // but in a production enterprise system, we might want to.
        // For now, we log it.
        return null;
    }
}
