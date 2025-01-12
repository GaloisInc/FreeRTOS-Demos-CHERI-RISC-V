#include "FreeRTOS.h"
#include "FreeRTOSConfig.h"
#include "task.h"
#include "bsp.h"
#include "plic_driver.h"

#include "portstatcounters.h"

#ifdef configUART16550_BASE
    #include "uart16550.h"
#endif

plic_instance_t Plic;

#define CHERI_COMPARTMENT_FAIL (-28)

#ifdef __CHERI_PURE_CAPABILITY__
    #include <stdint.h>
    #include <rtl/rtl-freertos-compartments.h>
    #include <cheri/cheri-utility.h>
    #include "portmacro.h"

    #if configCHERI_COMPARTMENTALIZATION
        static void inter_compartment_call( uintptr_t * exception_frame,
                                            ptraddr_t mepc )
        {
            uint32_t * instruction;
            uint8_t code_reg_num, data_reg_num;
            uint32_t * mepcc = ( uint32_t * ) *( exception_frame );

            mepcc -= 1; /* portASM has already stepped into the next isntruction; */

            instruction = mepcc;

            /* Decode the code/data pair passed to ccall */
            code_reg_num = ( *instruction >> 15 ) & 0x1f;
            data_reg_num = ( *instruction >> 20 ) & 0x1f;

            uint32_t cjalr_match = ( ( 0x7f << 25 ) | ( 0xc << 20 ) | ( 0x1 << 7 ) | 0x5b );

            /* Only support handling cjalr with sealed caps (inter-compartment calls) */
            if( ( *instruction & cjalr_match ) != cjalr_match )
            {
                printf( "Instruction does not match cjalr\n" );
                _exit( -1 );
            }

            /* Get the callee CompID (its otype) */
            size_t otype = __builtin_cheri_type_get( *( exception_frame + code_reg_num ) );

            void ** captable = rtl_cherifreertos_compartment_get_captable( otype );

            xCOMPARTMENT_RET ret = xTaskRunCompartment( cheri_unseal_cap( *( exception_frame + code_reg_num ) ),
                                                        captable,
                                                        exception_frame + 10,
                                                        otype );

            /* Save the return registers in the context. */
            /* FIXME: Some checks might be done here to check of the compartment traps and */
            /* accordingly take some different action rather than just returning */
            *( exception_frame + 10 ) = ret.ca0;
        }

    #endif /* ifdef __CHERI_PURE_CAPABILITY__ */

    static UBaseType_t default_exception_handler( uintptr_t * exception_frame )
    {
        #ifdef __CHERI_PURE_CAPABILITY__
            size_t cause = 0;
            size_t epc = 0;
            size_t cheri_cause;
            void * mepcc;
            #if configCHERI_COMPARTMENTALIZATION
                size_t xCompID = -1;
                rtems_rtl_obj * obj = NULL;
            #endif

            asm volatile ( "csrr %0, mcause" : "=r" ( cause )::);
            asm volatile ( "csrr %0, mepc" : "=r" ( epc )::);
            asm volatile ( "cspecialr %0, mepcc" : "=C" ( mepcc )::);

            size_t ccsr = 0;
            asm volatile ( "csrr %0, mtval" : "=r" ( ccsr )::);

            uint8_t reg_num = ( uint8_t ) ( ( ccsr >> 5 ) & 0x1f );
            int is_scr = ( ( ccsr >> 10 ) & 0x1 );
            cheri_cause = ( unsigned ) ( ( ccsr ) & 0x1f );

            #if configCHERI_COMPARTMENTALIZATION
            /* ccall */
            if( cheri_cause == 0x19 )
            {
                inter_compartment_call( exception_frame, epc );
                return 0;
            }

            /* Sealed fault */
            if( cheri_cause == 0x3 )
            {
                inter_compartment_call( exception_frame, epc );
                return 0;
            }
            #endif

            #if DEBUG
                for( int i = 0; i < 35; i++ )
                {
                    printf( "x%i ", i );
                    cheri_print_cap( *( exception_frame + i ) );
                }

                printf( "mepc = 0x%lx\n", epc );
                printf( "mepcc -> " );
                cheri_print_cap( mepcc );
                printf( "TRAP: CCSR = 0x%lx (cause: %x reg: %u : scr: %u)\n",
                        ccsr,
                        cheri_cause,
                        reg_num, is_scr );
            #endif

            #if configCHERI_COMPARTMENTALIZATION
                xCompID = xPortGetCurrentCompartmentID();
            #if configCHERI_COMPARTMENTALIZATION_MODE == 1
                obj = rtl_cherifreertos_compartment_get_obj( xCompID );

                if( obj != NULL )
                {
                    void * ret = xPortGetCurrentCompartmentReturn();
                    printf( "\033[0;31m" );
                    printf( "<<<< Fault in Task: %s: Compartment #%d: %s:%s\n", pcTaskGetName( NULL ), xCompID, obj->aname, obj->oname );
                    printf( "\033[0m" );

                    /* Caller compartment return */
                    *( exception_frame ) = ret;
                    *( exception_frame + 10) = CHERI_COMPARTMENT_FAIL;
                    return 0;
                }
            #elif configCHERI_COMPARTMENTALIZATION_MODE == 2
                rtems_rtl_archive* archive = rtl_cherifreertos_compartment_get_archive( xCompID );

                if( archive != NULL )
                {
                    void * ret = xPortGetCurrentCompartmentReturn();
                    printf( "\033[0;31m" );
                    printf( "<<<< Fault in Task: %s: Compartment #%d: %s\n", pcTaskGetName( NULL ), xCompID, archive->name );
                    printf( "\033[0m" );

                    /* Caller compartment return */
                    *( exception_frame ) = ret;
                    *( exception_frame + 10) = CHERI_COMPARTMENT_FAIL;
                    return 0;
                }

            #endif
            #endif /* if configCHERI_COMPARTMENTALIZATION */
        #endif /* ifdef __CHERI_PURE_CAPABILITY__ */

        while( 1 )
        {
        }
    }
#endif /* ifdef __CHERI_PURE_CAPABILITY__ */
/*-----------------------------------------------------------*/

/*-----------------------------------------------------------*/

/**
 *  Prepare haredware to run the demo.
 */
void prvSetupHardware( void )
{
    /* Resets PLIC, threshold 0, nothing enabled */

    #if PLATFORM_QEMU_VIRT || PLATFORM_FETT || PLATFORM_GFE
        PLIC_init( &Plic, PLIC_BASE_ADDR, PLIC_NUM_SOURCES, PLIC_NUM_PRIORITIES );
    #endif

    #ifdef configUART16550_BASE
        uart16550_init( configUART16550_BASE );
    #endif

    #if PLATFORM_GFE
        configASSERT(BSP_USE_DMA);
        PLIC_set_priority(&Plic, PLIC_SOURCE_ETH, PLIC_PRIORITY_ETH);
        PLIC_set_priority(&Plic, PLIC_SOURCE_DMA_MM2S, PLIC_PRIORITY_DMA_MM2S);
        PLIC_set_priority(&Plic, PLIC_SOURCE_DMA_S2MM, PLIC_PRIORITY_DMA_S2MM);
    #endif

    #if ((__CHERI_PURE_CAPABILITY__ && DEBUG) || configCHERI_COMPARTMENTALIZATION)
        /* Setup an exception handler for CHERI */
        for (int i = 0; i < 64; i++)
            vPortSetExceptionHandler( i, default_exception_handler );
    #endif

    #if configPORT_HAS_HPM_COUNTERS
        portCountersInit();
    #endif
}

    #if !(PLATFORM_QEMU_VIRT || PLATFORM_FETT || PLATFORM_GFE)
        __attribute__( ( weak ) ) BaseType_t xNetworkInterfaceInitialise( void )
        {
            printf( "xNetworkInterfaceInitialise is not implemented, No NIC backend driver\n" );
            return pdPASS;
        }

        __attribute__( ( weak ) )
        xNetworkInterfaceOutput( void * const pxNetworkBuffer, BaseType_t xReleaseAfterSend )
        {
            printf( "xNetworkInterfaceOutput is not implemented, No NIC backend driver\n" );
            return pdPASS;
        }
    #endif

/**
 * Define an external interrupt handler
 * cause = 0x8...000000b == Machine external interrupt
 */
BaseType_t external_interrupt_handler( UBaseType_t cause )
{
    BaseType_t pxHigherPriorityTaskWoken = 0;

    configASSERT( ( cause << 1 ) == ( 0xb * 2 ) );

    plic_source source_id = PLIC_claim_interrupt( &Plic );

    if( ( source_id >= 1 ) && ( source_id < PLIC_NUM_INTERRUPTS ) )
    {
        pxHigherPriorityTaskWoken = Plic.HandlerTable[ source_id ].Handler( Plic.HandlerTable[ source_id ].CallBackRef );
    }

    /* clear interrupt */
    PLIC_complete_interrupt( &Plic, source_id );
    return pxHigherPriorityTaskWoken;
}
