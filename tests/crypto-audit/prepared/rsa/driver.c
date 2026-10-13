/* Independent audit driver; only public test keys enter this process. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "rsa.c"

extern uint32_t audit_original_private(unsigned char *, const br_rsa_private_key *);
typedef struct { uint64_t before; unsigned char bytes[1840]; uint64_t after; } guarded_context;
static void guard_init(guarded_context *c) { memset(c, 0xa5, sizeof *c); }
static void guard_check(const guarded_context *c) {
    assert(c->before == UINT64_C(0xa5a5a5a5a5a5a5a5));
    assert(c->after == UINT64_C(0xa5a5a5a5a5a5a5a5));
}
static uint32_t read32(FILE *f) {
    unsigned char b[4]; assert(fread(b,1,4,f)==4);
    return (uint32_t)b[0] | (uint32_t)b[1]<<8 | (uint32_t)b[2]<<16 | (uint32_t)b[3]<<24;
}
static void readbytes(FILE *f, unsigned char *p, size_t n) { assert(fread(p,1,n,f)==n); }
static void check_output(unsigned char out[400], int64_t status, int64_t expected,
    const unsigned char *bytes, size_t len, unsigned index, const char *path) {
    if(status != expected || (len && memcmp(out+8,bytes,len))) {
        fprintf(stderr,"%s vector %u: expected %lld, got %lld or output mismatch\n",path,index,(long long)expected,(long long)status);
        abort();
    }
    for(size_t i=0;i<8;i++) assert(out[i]==0xa5 && out[392+i]==0xa5);
}
static void vectors(FILE *f) {
    unsigned count=read32(f), operations=0, factories=0;
    for(unsigned i=0;i<count;i++) {
        unsigned op=read32(f), prehash=read32(f);
        int64_t expected=(int32_t)read32(f);
        size_t lengths[3]; for(unsigned j=0;j<3;j++) lengths[j]=read32(f);
        size_t expected_len=read32(f), layout_len=read32(f);
        unsigned char a[3][2048]={{0}}, before[3][2048], expected_out[384], layout[1840];
        for(unsigned j=0;j<3;j++) { assert(lengths[j]<=sizeof a[j]); readbytes(f,a[j],lengths[j]); }
        assert(expected_len<=384 && layout_len<=1840);
        readbytes(f,expected_out,expected_len); readbytes(f,layout,layout_len);
        memcpy(before,a,sizeof a);
        unsigned char direct[400], prepared[400]; memset(direct,0xa5,sizeof direct); memset(prepared,0xa5,sizeof prepared);
        int64_t d=0, p=0;
        switch(op) {
        case 0: d=rsa_impl_validate_private_key(a[0],lengths[0]); break;
        case 1: d=rsa_impl_validate_public_key(a[0],lengths[0]); break;
        case 2: d=rsa_impl_public_key(a[0],lengths[0],direct+8); break;
        case 3: d=rsa_impl_sign(a[0],lengths[0],a[1],lengths[1],a[2],lengths[2],direct+8,prehash); break;
        case 4: d=rsa_impl_verify(a[0],lengths[0],a[1],lengths[1],a[2],lengths[2],prehash); break;
        default: abort();
        }
        check_output(direct,d,expected,expected_out,expected_len,i,"direct");
        guarded_context context; guard_init(&context);
        const size_t size=(op==1 || op==4) ? sizeof(prepared_public) : sizeof(prepared_secret);
        int64_t made=(op==1 || op==4) ? rsa_impl_prepare_public_key(a[0],lengths[0],context.bytes)
            : rsa_impl_prepare_secret_key(a[0],lengths[0],context.bytes);
        guard_check(&context);
        for(size_t j=size;j<sizeof context.bytes;j++) assert(context.bytes[j]==0xa5);
        if(made<0) {
            assert(!layout_len);
            for(size_t j=0;j<size;j++) assert(context.bytes[j]==0);
            p=made;
        } else {
            assert((size_t)made==size && layout_len==size && !memcmp(context.bytes,layout,size));
            factories++;
            unsigned char saved[1840]; memcpy(saved,context.bytes,sizeof saved);
            switch(op) {
            case 0: case 1: p=1; break;
            case 2: br_i31_encode(prepared+8,384,((prepared_secret *)context.bytes)->public.n); p=384; break;
            case 3: p=rsa_impl_sign_prepared(context.bytes,size,a[1],lengths[1],a[2],lengths[2],prepared+8,prehash); operations++; break;
            case 4: p=rsa_impl_verify_prepared(context.bytes,size,a[1],lengths[1],a[2],lengths[2],prehash); operations++; break;
            }
            assert(!memcmp(saved,context.bytes,sizeof saved)); guard_check(&context);
            /* A consistent composite CRT key reaches the self-check and fails. */
            if(op==3 && p==-1) for(size_t j=8;j<392;j++) assert(prepared[j]==0 && direct[j]==0);
        }
        check_output(prepared,p,expected,expected_out,expected_len,i,"prepared");
        assert(!memcmp(a,before,sizeof a));
    }
    assert(fgetc(f)==EOF);
    printf("%u independent direct/prepared vectors; %u full factory layouts; %u hot operations; bounds and immutability pass\n",count,factories,operations);
}
static void public_math(FILE *f) {
    unsigned expected_count=read32(f);
    unsigned char record[1977]; unsigned count=0;
    while(fread(record,1,sizeof record,f)==sizeof record) {
        unsigned char original_record[1977]; memcpy(original_record,record,sizeof record);
        unsigned char x[3][400]; for(unsigned j=0;j<3;j++) { memset(x[j],0xa5,400); memcpy(x[j]+8,record+384,384); }
        guarded_context ctx; guard_init(&ctx);
        assert(rsa_impl_prepare_public_key(record,384,ctx.bytes)==824);
        assert(!memcmp(ctx.bytes,record+1153,824));
        for(unsigned i=824;i<1840;i++) assert(ctx.bytes[i]==0xa5);
        unsigned char saved[1840]; memcpy(saved,ctx.bytes,sizeof saved);
        br_rsa_public_key pk={record,384,(unsigned char*)exponent,3};
        unsigned a=public_65537_prepared(x[0]+8,(prepared_public*)ctx.bytes);
        unsigned b=public_65537(x[1]+8,384,&pk), c=br_rsa_i31_public(x[2]+8,384,&pk);
        assert(a==record[1152] && b==a && c==a);
        for(unsigned j=0;j<3;j++) {
            assert(!memcmp(x[j]+8,record+768,384));
            for(unsigned k=0;k<8;k++) assert(x[j][k]==0xa5 && x[j][392+k]==0xa5);
        }
        assert(!memcmp(saved,ctx.bytes,sizeof saved));
        assert(!memcmp(original_record,record,sizeof record)); guard_check(&ctx); count++;
    }
    assert(feof(f) && count==expected_count); printf("%u public inputs match Python, fixed direct, prepared and unchanged upstream\n",count);
}
static void private_math(FILE *f) {
    unsigned count=read32(f);
    guarded_context keys[4]; unsigned char raw[4][960], saved_raw[4][960], saved[4][1840];
    for(unsigned i=0;i<4;i++) {
        unsigned char layout[1840];
        readbytes(f,raw[i],960); guard_init(&keys[i]);
        readbytes(f,layout,1840);
        assert(rsa_impl_prepare_secret_key(raw[i],960,keys[i].bytes)==1840);
        assert(!memcmp(keys[i].bytes,layout,1840)); guard_check(&keys[i]);
        memcpy(saved[i],keys[i].bytes,1840);
    }
    memcpy(saved_raw,raw,sizeof raw);
    for(unsigned i=0;i<count;i++) {
        unsigned key=read32(f), valid=read32(f); assert(key<4);
        unsigned char input[384], expected[384], modulus[384], x[3][400];
        readbytes(f,input,384); readbytes(f,expected,384);
        for(unsigned j=0;j<3;j++) { memset(x[j],0xa5,400); memcpy(x[j]+8,input,384); }
        br_rsa_private_key sk; assert(private_key(raw[key],960,&sk,modulus));
        unsigned a=private_prepared(x[0]+8,(prepared_secret *)keys[key].bytes);
        unsigned b=br_rsa_i31_private(x[1]+8,&sk), c=audit_original_private(x[2]+8,&sk);
        assert(a==valid && b==valid && c==valid);
        for(unsigned j=0;j<3;j++) {
            assert(!memcmp(x[j]+8,expected,384));
            for(unsigned k=0;k<8;k++) assert(x[j][k]==0xa5 && x[j][392+k]==0xa5);
        }
        for(unsigned k=0;k<4;k++) { guard_check(&keys[k]); assert(!memcmp(saved[k],keys[k].bytes,1840)); }
        assert(!memcmp(saved_raw,raw,sizeof raw));
    }
    assert(fgetc(f)==EOF);
    printf("%u interleaved private inputs across two keys and swapped factors match Python, upstream 8U, current direct, prepared\n",count);
    unsigned faults=0;
    /* Preserve all length headers; corrupt only plausible inline arithmetic state. */
    for(unsigned key=0;key<4;key++) for(unsigned kind=0;kind<5;kind++) {
        guarded_context damaged=keys[key]; prepared_secret *secret=(prepared_secret *)damaged.bytes;
        switch(kind) {
        case 0: secret->dp[191]^=1; break;
        case 1: secret->dq[191]^=1; break;
        case 2: secret->iq_mont[1]^=2; break;
        case 3: secret->p0i^=2; break;
        case 4: secret->q0i^=2; break;
        }
        unsigned char before[1840]; memcpy(before,damaged.bytes,1840);
        const unsigned char message[]="prepared fault self-check"; unsigned char salt[32]={0}, output[400];
        memset(output,0xa5,sizeof output);
        int64_t result=rsa_impl_sign_prepared(damaged.bytes,1840,message,sizeof message-1,salt,32,output+8,0);
        assert(result==INVALID_SECRET);
        for(size_t j=8;j<392;j++) assert(output[j]==0);
        for(size_t j=0;j<8;j++) assert(output[j]==0xa5 && output[392+j]==0xa5);
        assert(!memcmp(before,damaged.bytes,1840)); guard_check(&damaged); faults++;
    }
    printf("%u shaped CRT/Montgomery fault injections rejected with wiped output\n",faults);
}
int main(int argc,char **argv) {
    assert(argc==3); FILE *f=fopen(argv[2],"rb"); assert(f);
    if(!strcmp(argv[1],"vectors")) vectors(f);
    else if(!strcmp(argv[1],"public")) public_math(f);
    else if(!strcmp(argv[1],"private")) private_math(f);
    else abort();
    fclose(f); return 0;
}
