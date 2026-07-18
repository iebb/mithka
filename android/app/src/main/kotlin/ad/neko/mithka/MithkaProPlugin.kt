package ad.neko.mithka

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Google Play Billing bridge for the two Mithka Pro subscriptions. */
class MithkaProPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, PurchasesUpdatedListener {
    private val appContext = activity.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val distribution = determineDistribution()
    private val billingClient = BillingClient.newBuilder(appContext)
        .setListener(this)
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder()
                .enableOneTimeProducts()
                .build(),
        )
        .build()

    private val connectionWaiters = mutableListOf<(BillingResult?) -> Unit>()
    private var connecting = false
    private var storeAvailable = false
    private var isPro = false
    private var purchaseResult: MethodChannel.Result? = null
    private var requestedProductId: String? = null
    private var disposed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> getState(result)
            "getProducts" -> getProducts(result)
            "purchase" -> purchase(call.argument<String>("productId"), result)
            "restore" -> restore(result)
            "manage" -> manage(call.argument<String>("productId"), result)
            else -> result.notImplemented()
        }
    }

    override fun onPurchasesUpdated(
        billingResult: BillingResult,
        purchases: MutableList<Purchase>?,
    ) {
        when (billingResult.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val returnedPurchases = purchases.orEmpty()
                if (returnedPurchases.isEmpty()) {
                    finishPurchaseWithError(
                        "purchase_missing",
                        "Google Play did not return a purchase",
                    )
                    return
                }
                processPurchases(returnedPurchases) { acknowledgementError ->
                    if (acknowledgementError != null) {
                        finishPurchaseWithBillingError("acknowledge_failed", acknowledgementError)
                        return@processPurchases
                    }
                    val requested = requestedProductId
                    val matching = returnedPurchases.firstOrNull { purchase ->
                        requested == null || requested in purchase.products
                    }
                    if (matching == null) {
                        finishPurchaseWithError(
                            "purchase_missing",
                            "Google Play returned a different purchase",
                        )
                        return@processPurchases
                    }
                    val status = when (matching.purchaseState) {
                        Purchase.PurchaseState.PURCHASED -> "purchased"
                        Purchase.PurchaseState.PENDING -> "pending"
                        else -> "pending"
                    }
                    finishPurchase(status, matching.products.firstOrNull() ?: requested)
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> finishPurchase("cancelled")
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                queryActivePurchases { queryResult, activePurchases ->
                    if (queryResult.responseCode != BillingClient.BillingResponseCode.OK) {
                        finishPurchaseWithBillingError("restore_failed", queryResult)
                        return@queryActivePurchases
                    }
                    processPurchases(activePurchases) { acknowledgementError ->
                        if (acknowledgementError != null) {
                            finishPurchaseWithBillingError(
                                "acknowledge_failed",
                                acknowledgementError,
                            )
                        } else {
                            if (isPro) {
                                finishPurchase("purchased", requestedProductId)
                            } else {
                                finishPurchaseWithError(
                                    "purchase_missing",
                                    "No active Mithka Pro purchase was found",
                                )
                            }
                        }
                    }
                }
            }
            else -> finishPurchaseWithBillingError("purchase_failed", billingResult)
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        purchaseResult = null
        requestedProductId = null
        connectionWaiters.clear()
        billingClient.endConnection()
    }

    private fun getState(result: MethodChannel.Result) {
        if (distribution != DISTRIBUTION_PLAY_STORE) {
            result.success(stateMap())
            return
        }
        ensureConnected { connectionError ->
            if (connectionError != null) {
                result.success(stateMap())
                return@ensureConnected
            }
            queryActivePurchases { queryResult, purchases ->
                if (queryResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    storeAvailable = false
                    isPro = false
                    result.success(stateMap())
                    return@queryActivePurchases
                }
                processPurchases(purchases) {
                    // A purchased entitlement remains visible even when a transient
                    // acknowledgement call fails; it will be retried on next refresh.
                    result.success(stateMap())
                }
            }
        }
    }

    private fun getProducts(result: MethodChannel.Result) {
        if (distribution != DISTRIBUTION_PLAY_STORE) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        ensureConnected { connectionError ->
            if (connectionError != null) {
                result.error(
                    "store_unavailable",
                    safeBillingMessage(connectionError),
                    connectionError.responseCode,
                )
                return@ensureConnected
            }
            queryProductDetails { billingResult, productDetails ->
                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    result.error(
                        "products_failed",
                        safeBillingMessage(billingResult),
                        billingResult.responseCode,
                    )
                    return@queryProductDetails
                }
                val productsById = productDetails.associateBy(ProductDetails::getProductId)
                result.success(PRODUCT_IDS.mapNotNull { id -> productsById[id]?.toProductMap() })
            }
        }
    }

    private fun purchase(productId: String?, result: MethodChannel.Result) {
        if (productId !in PRODUCT_IDS) {
            result.error("invalid_product", "Unknown Mithka Pro product", null)
            return
        }
        if (distribution != DISTRIBUTION_PLAY_STORE) {
            result.error(
                "store_unavailable",
                "Mithka Pro purchases require the Google Play distribution",
                distribution,
            )
            return
        }
        if (purchaseResult != null) {
            result.error("purchase_in_progress", "A purchase is already in progress", null)
            return
        }
        purchaseResult = result
        requestedProductId = productId
        ensureConnected { connectionError ->
            if (connectionError != null) {
                finishPurchaseWithBillingError("store_unavailable", connectionError)
                return@ensureConnected
            }
            queryProductDetails { billingResult, productDetails ->
                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    finishPurchaseWithBillingError("products_failed", billingResult)
                    return@queryProductDetails
                }
                val details = productDetails.firstOrNull { it.productId == productId }
                val offer = details?.preferredOffer()
                if (details == null || offer == null) {
                    finishPurchaseWithError(
                        "product_unavailable",
                        "This Mithka Pro subscription is not available",
                    )
                    return@queryProductDetails
                }
                val productParams = BillingFlowParams.ProductDetailsParams.newBuilder()
                    .setProductDetails(details)
                    .setOfferToken(offer.offerToken)
                    .build()
                activity.runOnUiThread {
                    if (disposed) return@runOnUiThread
                    val launchResult = billingClient.launchBillingFlow(
                        activity,
                        BillingFlowParams.newBuilder()
                            .setProductDetailsParamsList(listOf(productParams))
                            .build(),
                    )
                    if (launchResult.responseCode != BillingClient.BillingResponseCode.OK) {
                        finishPurchaseWithBillingError("purchase_failed", launchResult)
                    }
                }
            }
        }
    }

    private fun restore(result: MethodChannel.Result) {
        if (distribution != DISTRIBUTION_PLAY_STORE) {
            result.success(stateMap("not_found"))
            return
        }
        ensureConnected { connectionError ->
            if (connectionError != null) {
                result.error(
                    "restore_failed",
                    safeBillingMessage(connectionError),
                    connectionError.responseCode,
                )
                return@ensureConnected
            }
            queryActivePurchases { queryResult, purchases ->
                if (queryResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    result.error(
                        "restore_failed",
                        safeBillingMessage(queryResult),
                        queryResult.responseCode,
                    )
                    return@queryActivePurchases
                }
                processPurchases(purchases) { acknowledgementError ->
                    if (acknowledgementError != null) {
                        result.error(
                            "acknowledge_failed",
                            safeBillingMessage(acknowledgementError),
                            acknowledgementError.responseCode,
                        )
                    } else {
                        result.success(stateMap(if (isPro) "restored" else "not_found"))
                    }
                }
            }
        }
    }

    private fun manage(productId: String?, result: MethodChannel.Result) {
        if (productId != null && productId !in PRODUCT_IDS) {
            result.error("invalid_product", "Unknown Mithka Pro product", null)
            return
        }
        val uri = Uri.parse(SUBSCRIPTIONS_URL).buildUpon().apply {
            if (productId != null) appendQueryParameter("sku", productId)
            appendQueryParameter("package", APPLICATION_PACKAGE)
        }.build()
        val intent = Intent(Intent.ACTION_VIEW, uri)
        if (intent.resolveActivity(appContext.packageManager) == null) {
            result.error(
                "manage_unavailable",
                "No application can open Google Play subscription management",
                null,
            )
            return
        }
        activity.runOnUiThread {
            try {
                activity.startActivity(intent)
                result.success(
                    buildMap<String, Any?> {
                        put("opened", true)
                        if (productId != null) put("productId", productId)
                    },
                )
            } catch (_: ActivityNotFoundException) {
                result.error(
                    "manage_unavailable",
                    "Google Play subscription management is unavailable",
                    null,
                )
            } catch (_: SecurityException) {
                result.error(
                    "manage_denied",
                    "Google Play subscription management could not be opened",
                    null,
                )
            } catch (_: Exception) {
                result.error(
                    "manage_failed",
                    "Google Play subscription management could not be opened",
                    null,
                )
            }
        }
    }

    private fun ensureConnected(callback: (BillingResult?) -> Unit) {
        if (disposed) return
        if (distribution != DISTRIBUTION_PLAY_STORE) {
            callback(unavailableBillingResult("Not installed by Google Play"))
            return
        }
        if (billingClient.isReady) {
            storeAvailable = true
            callback(null)
            return
        }
        connectionWaiters += callback
        if (connecting) return
        connecting = true
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                connecting = false
                storeAvailable =
                    billingResult.responseCode == BillingClient.BillingResponseCode.OK
                val error = if (storeAvailable) null else billingResult
                val waiters = connectionWaiters.toList()
                connectionWaiters.clear()
                waiters.forEach { it(error) }
            }

            override fun onBillingServiceDisconnected() {
                connecting = false
                storeAvailable = false
                val error = unavailableBillingResult("Google Play billing disconnected")
                val waiters = connectionWaiters.toList()
                connectionWaiters.clear()
                waiters.forEach { it(error) }
            }
        })
    }

    private fun queryProductDetails(
        callback: (BillingResult, List<ProductDetails>) -> Unit,
    ) {
        val products = PRODUCT_IDS.map { id ->
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(id)
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        }
        billingClient.queryProductDetailsAsync(
            QueryProductDetailsParams.newBuilder().setProductList(products).build(),
        ) { billingResult, detailsResult ->
            callback(billingResult, detailsResult.productDetailsList)
        }
    }

    private fun queryActivePurchases(
        callback: (BillingResult, List<Purchase>) -> Unit,
    ) {
        billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.SUBS)
                .includeSuspendedSubscriptions(false)
                .build(),
        ) { billingResult, purchases -> callback(billingResult, purchases) }
    }

    private fun processPurchases(
        purchases: List<Purchase>,
        completion: (BillingResult?) -> Unit,
    ) {
        val purchased = purchases.filter { purchase ->
            purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
                purchase.products.any(PRODUCT_IDS::contains)
        }
        isPro = purchased.isNotEmpty()
        val unacknowledged = purchased.filterNot(Purchase::isAcknowledged)
        if (unacknowledged.isEmpty()) {
            completion(null)
            return
        }
        var remaining = unacknowledged.size
        var firstError: BillingResult? = null
        unacknowledged.forEach { purchase ->
            billingClient.acknowledgePurchase(
                AcknowledgePurchaseParams.newBuilder()
                    .setPurchaseToken(purchase.purchaseToken)
                    .build(),
            ) { acknowledgementResult ->
                if (acknowledgementResult.responseCode != BillingClient.BillingResponseCode.OK &&
                    firstError == null
                ) {
                    firstError = acknowledgementResult
                }
                remaining -= 1
                if (remaining == 0) completion(firstError)
            }
        }
    }

    private fun stateMap(
        status: String? = null,
        productId: String? = null,
    ): Map<String, Any?> = buildMap {
        put("storeAvailable", storeAvailable && distribution == DISTRIBUTION_PLAY_STORE)
        put("isPro", isPro)
        put("distribution", distribution)
        put("isLimitExempt", distribution != DISTRIBUTION_PLAY_STORE)
        if (status != null) put("status", status)
        if (productId != null) put("productId", productId)
        // Google Play Billing does not expose subscription expiry client-side.
        // The optional expirationDateMillis key is intentionally omitted until
        // a verified Play Developer API backend can supply it.
    }

    private fun ProductDetails.toProductMap(): Map<String, Any?> {
        val phase = preferredOffer()?.pricingPhases?.pricingPhaseList?.lastOrNull()
        return mapOf(
            "id" to productId,
            "title" to title,
            "description" to description,
            "displayPrice" to (phase?.formattedPrice ?: ""),
            "period" to if (productId == PRODUCT_MONTHLY) "monthly" else "yearly",
        )
    }

    private fun ProductDetails.preferredOffer(): ProductDetails.SubscriptionOfferDetails? {
        val offers = subscriptionOfferDetails.orEmpty()
        val expectedPeriod = if (productId == PRODUCT_MONTHLY) "P1M" else "P1Y"
        val matchingPeriod = offers.filter { offer ->
            offer.pricingPhases.pricingPhaseList.lastOrNull()?.billingPeriod == expectedPeriod
        }
        return matchingPeriod.firstOrNull { it.offerId == null } ?: matchingPeriod.firstOrNull()
    }

    private fun finishPurchase(status: String, productId: String? = null) {
        val result = purchaseResult ?: return
        purchaseResult = null
        requestedProductId = null
        result.success(stateMap(status, productId))
    }

    private fun finishPurchaseWithBillingError(code: String, billingResult: BillingResult) {
        val result = purchaseResult ?: return
        purchaseResult = null
        requestedProductId = null
        result.error(code, safeBillingMessage(billingResult), billingResult.responseCode)
    }

    private fun finishPurchaseWithError(code: String, message: String) {
        val result = purchaseResult ?: return
        purchaseResult = null
        requestedProductId = null
        result.error(code, message, null)
    }

    private fun determineDistribution(): String {
        if (appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            return DISTRIBUTION_DEVELOPMENT
        }
        val installer = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                appContext.packageManager
                    .getInstallSourceInfo(appContext.packageName)
                    .installingPackageName
            } else {
                @Suppress("DEPRECATION")
                appContext.packageManager.getInstallerPackageName(appContext.packageName)
            }
        }.getOrNull()
        return if (installer == PLAY_STORE_PACKAGE) {
            DISTRIBUTION_PLAY_STORE
        } else {
            DISTRIBUTION_APK
        }
    }

    private fun unavailableBillingResult(message: String): BillingResult =
        BillingResult.newBuilder()
            .setResponseCode(BillingClient.BillingResponseCode.BILLING_UNAVAILABLE)
            .setDebugMessage(message)
            .build()

    private fun safeBillingMessage(result: BillingResult): String =
        result.debugMessage.takeIf(String::isNotBlank) ?: "Google Play billing is unavailable"

    companion object {
        private const val CHANNEL = "mithka/pro"
        private const val PRODUCT_MONTHLY = "ad.neko.mithka.pro.monthly"
        private const val PRODUCT_YEARLY = "ad.neko.mithka.pro.yearly"
        private val PRODUCT_IDS = listOf(PRODUCT_MONTHLY, PRODUCT_YEARLY)
        private const val APPLICATION_PACKAGE = "ad.neko.mithka"
        private const val SUBSCRIPTIONS_URL =
            "https://play.google.com/store/account/subscriptions"
        private const val PLAY_STORE_PACKAGE = "com.android.vending"
        private const val DISTRIBUTION_PLAY_STORE = "play_store"
        private const val DISTRIBUTION_APK = "apk"
        private const val DISTRIBUTION_DEVELOPMENT = "development"
    }
}
